# Axial Mobile — working notes

A SwiftUI/iOS 26 POC rebuilding the sellside project experience from the
Angular web app (`../FE-app`). `docs/CHALLENGES.md` is the running log of
real obstacles and the decisions taken — read it before relitigating one,
and add to it when a new one turns up.

## View identity is the performance model

Most of the jank in this app has had one cause: a view's *type* changing
between renders. SwiftUI can only update a view in place when its identity is
stable; change the type and it destroys the old one and builds a new one.
That reads as a blink, breaks the iOS 26 Liquid Glass morph, and resets
scroll position and `@State`.

**Vary data and modifiers. Don't vary structure.**

```swift
// Wrong — two branches, so the fetch landing rebuilds the whole screen.
switch loadState {
case .loading: ScrollView { Header(summary: summary); Skeleton() }
case .loaded(let d): ScrollView { Dashboard(dashboard: d) }
}

// Right — one tree, optional data, only the genuine swap transitions.
ScrollView { Dashboard(summary: summary, dashboard: dashboard, isLoading: …) }
```

Concretely, in this codebase:

- Pass **optional data** into one view rather than switching between a
  loading view and a loaded view. A loaded state that refines a borrowed one
  is not a different screen.
- Branch only where the shape is genuinely different — a cold failure with
  nothing to show, for instance.
- When a swap is real (skeleton → content), give both branches
  `.transition(.opacity)` and put `.animation(_:value:)` on the container, so
  it cross-fades instead of popping.
- `if let` inside a `@ViewBuilder` is a type change. So is `switch`. So is a
  conditional modifier (`if x { view.foo() } else { view }`) — prefer
  `.disabled(…)`, `.opacity(…)`, or passing nil.

### Toolbars are stricter

- A `ToolbarItem` whose content changes type is removed and re-inserted, and
  loses the glass morph. Keep one `Button`/`Menu` and change its label or
  disabled state instead.
- `.principal` is the legacy `UINavigationItem.titleView` path and sits
  outside the bar's glass, so it never morphs. iOS 26's `.title` is the real
  title slot — but it animates with the *title*, which means no animation at
  all for a custom view. Controls that need to animate belong in
  `.topBarLeading` / `.topBarTrailing`.
- Adjacent bar items share one glass capsule. `ToolbarSpacer(.fixed,
  placement:)` splits them; `.sharedBackgroundVisibility(.hidden)` opts an
  item out entirely (use it when the content brings its own background, or
  the bar will size it like an icon button and squash it).
- Don't apply `.buttonStyle(.glass)` inside a toolbar — the bar already
  provides glass, and you'll get a container inside a container. `.glass` is
  for buttons in *content*.
- To expand a control into a detail panel, use `.popover` with
  `.presentationCompactAdaptation(.popover)` and `.presentationBackground(
  .clear)`, and put your own `.glassEffect` on the content. Clearing the
  background removes the arrow, which is what makes it read as the control
  zooming open and collapsing back into itself. `GlassEffectContainer` +
  `glassEffectID` is the other way to morph between two glass shapes, but it
  has to be laid out so the expansion doesn't resize the page, and it gives
  up the popover's free dismissal behaviour.
- A zoom transition out of a bar button needs
  `matchedTransitionSource(id:in:)` on the **`ToolbarItem`**, not on the
  `Button` inside it — iOS 26 added a `ToolbarContent` overload for this.
  The `View` version compiles and silently does nothing there, because the
  item is bridged to UIKit; the sheet just cross-fades instead.
- **Don't anchor a popover to a bar item** if its content has its own
  background. The bar hides the source item while the popover is up and
  restores it through the glass morph afterwards — so a coloured capsule
  spends several hundred milliseconds as a blurred smear with its background
  dropped out, and nothing in your code drives that animation. Anchor to
  content instead, or make the bar item plain enough that the system is
  morphing its own glass rather than your artwork.

### Lists and scrolling

- `LazyVStack` for anything that can grow (deals, projects). A project can
  carry hundreds of rows.
- Patch a single element rather than replacing the array — see
  `ProjectDashboard.applying(_:)`.
- Rows should be cheap: no nested `GeometryReader`, no per-row date
  formatters, no work that could be computed once on the model.

## Architecture

- **Stores** are `@Observable`, app-scoped, injected via `.environment` in
  `App.swift`, and depend on `any APIRequesting` — never on `APIClient`
  directly, so tests can drive them with `StubAPI`.
- **Mutations patch local state from their own response.** Every endpoint
  that returns a whole object funnels through one `apply(_:)`; nothing
  re-GETs after a save, and the projects list is patched at the same time so
  a card can't drift from its detail screen. This is the pattern — keep new
  endpoints inside it.
- **Views are dumb.** Business rules live in pure functions on models or
  small value types (`ProjectAction`, `ManageProjectMenu`,
  `ProjectStatusDetail`, `SellsideDeal.bucket`), so they're unit-testable
  without a host app. If a view is deciding something, move it.
- **App-wide sheets are presented from the root.** The Account sheet's
  `.sheet` lives once in `ContentView`, above every navigation stack, and
  `AccountPresenter` (environment) decides when it's up and which page it
  opens on. Screens call `present(_:)`; they never own that sheet.
- **Project setup is the exception to app-scoped stores.** A
  `ProjectSetupSession` lives exactly as long as one open wizard. Its form
  is a single `SetupForm` value, so every edit revalidates and autosaves
  through one `didSet`. New fields go into a step's form struct, with
  `write(into:)` and `validate`, not into views. See CHALLENGES #18.
- **Borrow before fetching.** A pushed screen renders from state we already
  hold (`ProjectsStore.project(withIntentId:)`) and refines it when the fetch
  lands. Skeletons are for data we genuinely don't have.

## Mirroring the web

- Name the web source in the doc comment — file and symbol — so the next
  person can diff it. Tests do the same.
- The web app is a reliable guide to the *shape* of a rule, **not** to
  endpoints. `FE-app` has been behind the deployed API more than once. Verify
  paths against the running API; a 404 means stale web source before it means
  a mobile typo.
- Mirror web quirks rather than fixing them unilaterally, and say so in a
  comment. Two apps disagreeing is worse than both being odd the same way.
- Unknown enum values decode to `.unknown` and degrade safely — a shipped
  binary meets values added after it was built, which the web never does.

## Conventions

- Swift Testing (`@Test`, `#expect`), not XCTest, for unit tests.
- Tests state the claim in the name and cite the web source in a comment.
- No hardcoded dates or times in assertions — format expectations the same
  way the code does, or inject `now`. (A literal "December 12, 2025" passes
  in UTC and fails in New York.)
- `AxialColor` / `TagPalette` / `ChartPalette` only; no ad-hoc hex in views.
- Respect `accessibilityReduceMotion` for animations *we* drive; leave
  system-driven ones alone.
- Accessibility identifiers on anything a UI test will need (see
  `docs/CHALLENGES.md` #12 for why they can't run yet).

## Build & test

The user builds and tests in Xcode. Don't run builds. A fast syntax check:

```sh
find "Axial Mobile" Tests -name "*.swift" -print0 \
  | xargs -0 xcrun --sdk iphoneos swiftc -parse -target arm64-apple-ios26.0
```
