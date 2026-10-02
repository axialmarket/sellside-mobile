# Mobile POC — Challenges & Future Hurdles

A running log of the real obstacles in translating the Axial web app to a
native mobile experience. Each entry: the problem, what the POC does about
it (if anything), and what a production solution needs.

## 1. Environment switching (raised 2026-09-21)

**Problem.** The web app gets its environment at deploy time; a mobile binary
is baked and shipped. Today `API_BASE_URL` is fixed per build configuration
(.xcconfig). We want one internal build that can point at a local desktop API,
zinc, or any elemental (oxygen, iron, carbon, …) without a TestFlight build
per environment.

**POC state.** `APIEnvironment` resolves the base URL from a `UserDefaults`
override (`api_base_url_override`) first, then the xcconfig value. The seam
exists; no switcher UI yet.

**Production path.**
- Internal/TestFlight builds: debug-only environment picker writing the
  override (elemental presets + free-form URL + `http://<mac>.local` for a
  desktop API; local HTTP needs a debug-only ATS exception).
- App Store builds: compile the switcher out; lock to production.
- App Review: reviewed builds should hit production infrastructure with a
  demo account containing production-like data. Swapping backends after
  approval is contrary to review guidelines — plan accounts, not endpoint
  tricks.
- Staging.xcconfig / Production.xcconfig are currently empty — the Release
  build has no API_BASE_URL and would crash at launch. Fill before any
  TestFlight distribution.

## 2. xcconfig `//` comment gotcha (fixed)

`API_BASE_URL = https://…` silently truncated to `https:` because `//`
begins a comment in xcconfig. Values must be written
`https:/$()/host/path`. Worth a lint/CI check eventually.

Related (fixed 2026-09-21): the .xcconfig files existed on disk but were
never attached to any build configuration (`baseConfigurationReference`),
so `$(API_BASE_URL)` expanded to empty. The original hardcoded-URL
concatenation in `AppConfig` masked both failures — the app "worked"
without any config actually flowing through. Debug → Development.xcconfig
and Release → Production.xcconfig are now attached at the project level.

## 3. Design-token drift

Colors are hand-copied from fe-app's generated SCSS tokens
(`_colors.scss`) into `AxialColor.swift`. No pipeline keeps them in sync.
Future: generate Swift from the same token source the web build uses.

## 4. Brand typography

Web uses "TT Interphases Pro Variable". Not embedded in the app —
licensing for mobile embedding is unverified and SF Pro gives Dynamic
Type/accessibility for free. Revisit with the design team if brand type
on mobile becomes a requirement.

## 5. Grid → mobile translation

The web projects table (ag-grid) offers column sorting, regrouping, and
quick filter. Cards + fixed status sections replace it on mobile. Search,
filtering, and sort options need a mobile-native design later.

## 6. Auth/session lifecycle

POC handles: stored credentials on launch, bearer tokens per request,
local sign-out on 401. Not handled: proactive token refresh UX, revocation,
biometric re-auth, multi-account. Auth0 `credentialsManager` refreshes
tokens implicitly, but failure modes surface as a blunt "session expired."

## 7. Pagination & data volume

`GET /api/sellside-projects` supports only `limit`. Fine for typical
seller portfolios; an account with hundreds of projects gets one big
payload and one big list render. Needs server-side paging for scale.

## 8. Gateway IP allowlist blocks mobile devices (found 2026-09-21)

**Problem.** `GET /api/sellside-projects` from the app returns
`403 RBAC: access denied`. Root cause (confirmed in the dev cluster): each
elemental's API hostname (e.g. `zinc-api.axialmarket.com`) is served by TWO
Envoy Gateway routes — `axial-api` on the `internal` gateway (unrestricted)
and `axial-api-external` on the `public` gateway, which carries a
`SecurityPolicy` (`envoy-gateway-system/public-gateway-ip-allowlist`) with
`defaultAction: Deny` and a three-IP allowlist. Traffic from
office/VPN/allowlisted IPs reaches the API; anything else (a phone on
cellular or home Wi-Fi, a TestFlight tester, App Review) is denied at the
gateway — the token is never even examined. Nothing app- or Auth0-side can
fix this.

**Evidence.** Same request works from an allowlisted network path (curl on
a VPN'd Mac reaches FastAPI and gets its JSON 401) but gets Envoy's
plaintext RBAC deny otherwise; no 403 path exists in axial-api for this
route; the policy is ~5 weeks old, which is why earlier `/users/me` testing
predated the lockdown and "worked".

**Decision (2026-09-21).** The VPN-only posture for elementals is
intentional and stays. We will NOT override it (the `demo` elemental's
`demo-api-open-access` SecurityPolicy shows how one would, if ever needed
for e.g. an external demo).

**Dev workflow implications.**
- iOS Simulator on a VPN'd Mac shares the Mac's network path → full access.
  This is the default development loop (haptics excepted — those need
  hardware).
- Physical devices need the VPN on the phone itself. That also covers the
  local-API case: each dev's `<name>-api.axialmarket.com` DNS record points
  at their Mac's VPN IP, and the local docker nginx serves 443 with the
  valid `*.axialmarket.com` wildcard cert — so a VPN'd phone reaches the
  desktop API over real HTTPS (no ATS exceptions). Point the app there via
  the `APIEnvironment` override, e.g. the Xcode launch argument
  `-api_base_url_override https://<name>-api.axialmarket.com/api`.
  Without VPN on the same Wi-Fi, a dnsmasq override on the Mac works but
  is per-network fiddling.
- TestFlight testers and App Review can never reach an elemental. Any
  externally-distributed build must target an environment that is reachable
  from arbitrary IPs — this constraint, not tooling, is the real shape of
  the "which environment does a build point at" challenge (#1).

## 9. Telemetry & observability

Web has established analytics/error tooling; the app has `print`.
Production needs crash reporting, API failure metrics, and analytics
before any real rollout.

## 10. Patch-don't-refetch, and what goes stale (raised 2026-09-29)

**The pattern.** Mutations on a project return the whole object
(`PATCH /api/intents/{id}` → `{ intent, is_first_recommendation }`; the
status-change POSTs → the intent). So a save updates local state from its
own response; it never triggers a follow-up GET. `ProjectDetailStore`
funnels every whole-project response through `apply(_:)`, which caches it
by intent id and patches the matching projects-list row, so the card and
the dashboard can't disagree.

**Consequences to watch.**
- Two models describe one project. `/sellside-projects` rows carry the
  recommended/contacted/interested counts; `/api/intents/{id}` doesn't.
  `SellsideProject.merging(_:)` therefore overlays only the fields the
  detail payload is authoritative for and leaves the counts alone. Every
  field added to `ProjectDetail` needs that same call made deliberately.
- A cached detail has no TTL and no invalidation. Reopening a project
  renders from cache (the point — no fetch), so a change made on the web,
  or by a teammate, isn't picked up until pull-to-refresh. Fine at POC
  scale; a real app wants a staleness window or push-driven invalidation.
- The counts themselves only refresh with the list. Actions taken inside a
  project (sharing a teaser, say) will move counts the dashboard knows
  about but the list row doesn't. Either the detail endpoint grows the
  stats, or those actions patch the row explicitly.

**Borrowed state on open.** The dashboard header renders from the tapped
list row immediately and swaps to the fetched project when it arrives, so
only data the list can't supply ever shows a skeleton. Two things follow:
the row and the project must map to the same header (`ProjectSummary`
covers both, and a test pins them together), and a row that's gone stale
will briefly show the old name before the GET corrects it. Acceptable while
the list is minutes old at most; worth revisiting if the list starts being
cached across launches.

**Ids.** `public_id` on list rows is a hyphenated UUID; `/api/intents/{id}`
takes and echoes the hyphen-stripped form (fe-app's `removeHyphensFromId`).
`IntentID.normalized(_:)` strips on both sides so cache keys always match.

## 11. Keeping mobile's business rules in step with the web (raised 2026-09-30)

**Problem.** The web app decides a great deal in code that mobile now has to
decide too: which status transitions a project is offered, what each one
posts, how the counterparty list is built. Reimplementing that in Swift
means two copies of rules that were never designed to have two copies, and
nothing fails loudly when the web changes one.

**What the POC does.** Rules are data, not branching inside views, and each
one is unit-tested against the web's table with the source file named in the
test:

- `ProjectAction.availableStates` ↔ `SELL_INTENT_STATUS_MENU_OPTIONS`'
  `when` predicates (sell.constants.ts).
- `ProjectAction.path` ↔ `updateSellIntentState`'s switch
  (intent.api.service.ts).
- `CounterpartyOption.options(from:)` ↔ `parsePossibleCounterParties` +
  `filterCompanies`, and `CounterpartyInfo.make` ↔ `submitForm`'s payload
  (update-intent-with-counterparty-modal.component.ts).

**And the web source isn't the contract.** The sellside deals path was
copied from `getSellsideDealsRows` as `/api/sellside/deals/{intentId}`; the
deployed API 404s that and serves
`/api/intents/sellside/{intentId}/deals`. fe-app's checkout is simply
behind. So reading the web app tells you the *shape* of a rule but not
reliably the endpoint — verify paths against the running API, and treat a
404 as "the web source is stale" before assuming a mobile typo.

The tests don't detect web-side drift on their own — they make it cheap to
diff by hand, and they stop a mobile refactor from silently changing a rule.

**Production path.** The durable fix is for the rules to stop being
frontend-owned: have the API tell a client which transitions are legal for a
project rather than every client deriving it from `supply_state`. Short of
that, a shared spec (generated constants, or a contract test both apps run)
beats a comment pointing at a TypeScript file.

**`.unknown` is mobile-only.** A shipped binary can meet a `supply_state`
added after it was built. Web ships fresh code with the API, so it never
has this case. Mobile decodes it to `.unknown` and offers no status actions
at all — a project in a state the app can't reason about is read-only rather
than transitionable into a wrong state.

## 12. UI tests need a seam the app doesn't have yet (raised 2026-09-30)

**Problem.** Unit tests now cover the stores (via `StubAPI`, an
`APIRequesting` stub) and the pure rules. XCUITests can't run at all: the
app launches into Auth0, and the API is VPN-gated for anything but an
allowlisted network path (#8). A UI test on a clean CI machine reaches the
sign-in screen and stops.

**What's needed.** A launch-argument-driven mode that swaps `APIRequesting`
for a fixture-backed stub and short-circuits `AuthenticationService` —
roughly `-ui-testing-fixtures projects-in-market`. `App.swift` already
builds the object graph in one place, so the injection point exists; the
stub, the fixtures and the auth bypass don't. Views carry accessibility
identifiers (`manage-project-menu`, `project-action-<case>`,
`counterparty-picker`, …) so the tests have stable hooks once they can run.

**Worth noting.** The auth bypass has to be compiled out of App Store
builds, same as the environment switcher in #1 — it's the same debug-only
seam problem, and both should land together.

## 13. Sections: one endpoint, and drilling down rather than switching (raised 2026-09-30)

The web's sell container has three tabs — Recommended / Contacted /
Interested — with the project summary in a header above them.

**All three lists come from the deals response.** Web feeds its Recommended
tab from a second endpoint (`/api/sellside/recommendations/{intentId}`) and
partitions the deals on `is_interested` for the other two. The deals payload
already distinguishes all three, so mobile derives them in one pass —
`SellsideDeal.bucket`:

- `is_interested` → Interested. This is the web's own rule
  (`getContactedTargetsRows` filters on exactly it) and takes priority.
- `supply_status` of `recommended` or `not_shared` → Recommended: Axial has
  put the member forward and nothing has been shared.
- everything else → Contacted, including an unrecognized status, so a deal
  can never vanish from every section.

That last rule is the one to check against production data; the deals
endpoint may not return `recommended`-status rows at all, in which case that
card simply never appears. It's a single predicate in one place, and
`ProjectSectionTests` states each claim in a named test.

**Sections are pushed, not switched.** The project screen is its dashboard;
the three sections are cards in a row showing a count and a chevron, each
pushing its own screen. Three earlier attempts and why they lost:

- *A nested tab bar.* A bottom tab bar promises persistence and top-level
  scope. These sections belong to one project and vanish when you leave it,
  and a real tab bar at the app root would later collide with it.
- *A segmented control.* Correct semantics, but "Recommended" truncates at
  four segments on a phone, and worse at large Dynamic Type sizes —
  segmented controls truncate rather than wrap or shrink. Apple keeps those
  labels terse (`D / W / M / 6M / Y`) for exactly this reason.
- *A scrollable chip row.* Works at any label length and has heavy
  real-world precedent, but it's a non-standard control, and drilling down
  buys something better: each list gets a full-width title, its own scroll
  position, and room for its own toolbar as it grows.

Drilling down costs a tap each way. If sellers turn out to bounce between
Contacted and Interested constantly, that's the signal to revisit.

**Other consequences.**

- **The cards are the numbers *and* the navigation.** A count you can't act
  on is trivia; a list you can't size up before opening costs a tap to learn
  nothing.
- **Recommended's card is conditional; Contacted and Interested always
  show.** Web shows all three and swaps in an explainer when one is empty
  (`SellEmptyState.ZERO_RECS`, `SMART_SHARE`, …). Mobile hides the card,
  which includes the SmartShare case — so a seller running SmartShare loses
  the explanation the web gives them. That copy is real product content and
  should come across; until it does, hiding beats a card that leads nowhere.
- **Recommended rows carry no actions.** The per-deal menu is the
  *contacted* grid's, and marking an NDA sent on a member you've never
  shared with is nonsense. Web's recommended grid has its own set — share
  teaser, ignore, pin — which mobile doesn't have yet.
- **Two requests, not three.** Intent and deals resolve together; the
  sections come out of the deals, so the cards can't shift after first
  paint.
- **`ProjectDashboard.deals(in:)` is the only way in.** The SmartShare rule
  lives there rather than in each caller, so reaching for `deals` directly
  can't bypass it.

## 14. The status hover has no touch equivalent (raised 2026-09-30)

Web puts a hover card on the project status tag: where the project stands,
how long it's been there, and how it's being shared. Touch has no hover, so
the detail has to be asked for — the status moved into the navigation bar
as a tappable pill that opens the same two rows in a popover. Keeping it in
the bar also means it stays true and visible at every scroll position,
which the in-content header couldn't promise.

**Faithfully mirrored** (`ProjectStatusDetail`): the per-status date field,
the split between "Since <date>" and "N days on Axial", the sharing
precedence (inbound inquiry → SmartShare → manual review), and
`smartshareExpiryInDays` flooring at zero.

**Two knowing deviations.**

- *The account capability checks are missing.* Mobile never fetches the
  current account, and two web rules depend on it. The inbound-inquiry row
  needs `is_inbound_inquiry_enabled` **and**
  `account.can_enable_inbound_inquiry`; mobile goes on the project's flag
  alone. Sharing Settings is greyed when
  `!account.can_share_teasers && !intent.isApproved()`; mobile drops that
  clause, so the item can stay tappable where the web would grey it. The
  second gates a feature rather than a label, so it matters more.

  **Decided (2026-09-30):** the account arrives with `/me`, which becomes a
  hard gate — if that request fails the app is unusable, not
  degraded. That makes it a launch-blocking fetch alongside the credential
  check, not a per-screen concern, and it removes the "what if the account
  is missing" branch from every consumer. `approval_state` goes on
  `ProjectDetail` at the same time, since it's unusable without the account.
  Detail work deferred until the POC is done.
- *The date fields are milliseconds.* fe-app hands these numbers to
  `new Date(n)`. A naive `Date(timeIntervalSince1970:)` puts every project
  in 1970, which is a silent, plausible-looking bug — `EpochDate` exists to
  keep that decision in one place, and it treats 0 as unset rather than as
  1 January 1970.

**Also worth fixing:** `SELL_INTENT_STATUS_OPTIONS` gives `dead` a red tag
colour; mobile renders it plain, because `_colors.scss`'s red tag tokens
were never copied into `TagPalette` and guessing a hex is worse than being
consistently plain. Same root cause as #3.

**A web slip we mirrored rather than corrected:** `under_review` reads
`inboundInquiryDate` for its subtitle where every other status reads its own
milestone. It looks wrong, but the two apps disagreeing about a date is
worse than both being odd in the same way. Worth raising with the web team.

## 15. Filters: the web's grid columns, scaled to the card (raised 2026-10-02)

The web filters the sellside projects list through ag-grid column filters
(`MarketDealsGridComponent`, market-deals-grid.component.ts). Mobile has no
columns, only cards, so it offers filters for what the card shows and
reduces each one to its most common use. The full mapping is in the doc
comment on `ProjectFilter`. In short:

- **Kept as-is:** Status and Contact are set filters on both. Values within
  one filter OR together and separate filters AND, as in ag-grid.
- **Simplified:** Industries is free text over "vertical + activity" on the
  web. Mobile offers a set of the sector *names* the card prints, because
  search already handles free text. Created is a date-range editor on the
  web and a few trailing windows on mobile. The three count columns are
  number filters on the web and "has any" toggles on mobile, plus "has new
  recommendations".
- **Dropped:** Project Type, because it isn't on the card.

**Not persisted.** The web saves grid state to table preferences on the
server (`TablePreferencesStore`). Mobile keeps filters in view state, so
they last until the app is relaunched. Sharing the web's saved preferences
would mean translating ag-grid filter models, which isn't worth doing until
someone asks for it.
