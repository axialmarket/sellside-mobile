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
