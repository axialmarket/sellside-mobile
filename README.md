# Sellside Mobile

A native SwiftUI app for Axial's sellside: a seller's projects, the project
dashboard and its action items, the member lists, and each deal. It's a proof
of concept for a focused iPhone app alongside the web app (`FE-app`), built
on the same API.

- **Platform:** iPhone, iOS 26.0 or later
- **Language:** Swift, SwiftUI, Swift Testing
- **Dependencies:** [Auth0.swift](https://github.com/auth0/Auth0.swift) (Swift Package Manager; resolved automatically)
- **App name on the device:** Axial For Sellers (`com.axial.www.Axial-For-Sellers`)

## Requirements

- A Mac with **Xcode 26** or later.
- An Axial login on the environment the build points at.
- **The VPN.** The API environments the app uses today are VPN-only. The
  simulator uses the Mac's connection, so the Mac needs the VPN. A physical
  device needs the VPN app connected **on the phone itself**. Off the VPN, the
  app shows a "Connect to the VPN" screen.
- To run on a device or build for TestFlight: membership in Axial's Apple
  developer team (`UPG929H74U`). Ask an admin to add your Apple ID.

## Run on the simulator

1. Connect the Mac to the VPN.
2. Open `Axial Mobile.xcodeproj` in Xcode. Swift Package Manager fetches
   Auth0 the first time.
3. Pick the **Axial Mobile** scheme and an iPhone simulator in the toolbar.
4. Press **⌘R**, then sign in with your Axial account.

Debug builds use `Development.xcconfig`, which points at the zinc elemental.

## Run on a device

1. In Xcode, open **Settings › Accounts** and add the Apple ID that's on
   Axial's developer team.
2. Select the **Axial Mobile** target › **Signing & Capabilities**. Leave
   "Automatically manage signing" on and confirm the team is Axial's.
3. Connect the iPhone by cable, or pair it over Wi-Fi in **Window › Devices
   and Simulators**. The first time, turn on **Developer Mode** on the phone
   (Settings › Privacy & Security) and trust the Mac.
4. Turn on the VPN on the phone.
5. Pick the phone as the run destination and press **⌘R**.

Haptics only work on a device. Everything else works in the simulator.

### Pointing at a different API

The API host comes from `API_BASE_URL` in the active `.xcconfig`. For a
one-off run against another host, such as your own local API, add a launch
argument to the scheme (**Product › Scheme › Edit Scheme › Run › Arguments**):

```
-api_base_url_override https://<name>-api.axialmarket.com/api
```

## Tests

- **Unit tests** (Swift Testing, in `Tests/`): **⌘U**, or the Test navigator.
  They cover the business rules (statuses, actions, filters, the mirrored web
  logic) and need no network.
- **UI tests** (XCTest, in `UI Tests/`): these run the app in the simulator
  with sample data. They launch with `-ui-testing`, which signs in without
  Auth0 and swaps the API for fixtures (`UITesting/FixtureAPI.swift`), so they
  need neither a login nor the VPN. They run one at a time, so you can watch
  them in the simulator.

From the command line:

```sh
xcodebuild test -project "Axial Mobile.xcodeproj" -scheme "Axial Mobile" \
  -destination "platform=iOS Simulator,name=iPhone 17"
```

## Build for TestFlight

1. Pick **Any iOS Device (arm64)** as the destination.
2. **Product › Archive**. Archives build the **Release** configuration, which
   reads `Production.xcconfig`.
3. In the Organizer: **Distribute App › App Store Connect › Upload**.

`Production.xcconfig` currently points at zinc with `API_REQUIRES_VPN = YES`,
so TestFlight builds are for internal testers with the VPN on their phones.
Before App Review or any external tester:

- Point `API_BASE_URL` at the public API and delete `API_REQUIRES_VPN`. The
  two change together.
- Move Auth0 to the production tenant. The domain is set in
  `Axial Mobile/Auth0Config.swift` and the client ID in `Auth0.plist`.

## Configuration

| File | Used by | What it sets |
|---|---|---|
| `Development.xcconfig` | Debug (Run, Test) | `API_BASE_URL`, `API_REQUIRES_VPN` |
| `Production.xcconfig` | Release (Archive) | `API_BASE_URL`, `API_REQUIRES_VPN` |
| `Axial-Mobile-Info.plist` | both | Passes those two settings into the app |
| `Auth0.plist` | both | Auth0 client ID |

The app stores no member data on the device. Responses are held in memory
only, and the network session caches nothing to disk.

## Project layout

```
Axial Mobile/
  API/             Networking: APIClient, APIRequesting, errors
  Models/          Decoded API models (nonisolated; decoded off the main actor)
  DesignSystem/    Colours, radii, card surfaces, shared controls
  Features/
    Projects/      The projects list
    ProjectDetail/ The dashboard, member lists, row and bulk actions
    DealDetail/    One deal: profile, messages, files, comments
    ProjectActions/ Action item sheets (CIM note, follow-up, financials)
    Account/, Auth/
  UITesting/       The -ui-testing seam and its fixtures (Debug only)
Tests/             Unit tests
UI Tests/          UI tests
docs/CHALLENGES.md Decisions and obstacles, numbered; read before changing course
CLAUDE.md          Working notes: performance rules, architecture, conventions
```

## Working on it

- Read `CLAUDE.md` first. It covers the patterns the code relies on: stable
  view identity, stores that patch themselves from responses, and the design
  tokens.
- Many rules mirror the web app. Comments name the `FE-app` file and symbol
  they come from, so the two can be compared. Where mobile departs from the
  web, the comment says so.
- `docs/CHALLENGES.md` records each real obstacle and the decision taken.
  Add to it when you hit a new one.
