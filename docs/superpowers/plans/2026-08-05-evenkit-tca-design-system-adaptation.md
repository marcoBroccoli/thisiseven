# EvenKit + TCA + design-system adaptation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the iOS app into EvenKit (TCA Features + Dependency clients). Treat the app as **unfinished**: scaffold → feature shells → refine to `even-design-system/` one by one.

**Architecture:** Pure TCA `AppReducer` owns boot → onboarding stack → ready chrome. Features map to the five design flows. Side effects live in `*Client` / `*ClientLive`; `DI` is the only Live importer. Temporary `.legacyReady` bridges old UI until Features replace it.

**Phases:** (1) Scaffold green (2) Build Features rough (3) Refine UI per flow — pixel 1:1 is Phase 3 only.

**Tech Stack:** Swift 6+, **iOS 18+** iPhone app + widgets, **watchOS 11+** Watch app + Watch widgets, latest TCA + Dependencies, modern Apple SDK APIs, xcodegen, Go `evend` API. Prefer structure over verify loops until Features / Watch / widgets are wired.

**Spec:** [`docs/superpowers/specs/2026-08-05-evenkit-tca-design-system-adaptation.md`](../specs/2026-08-05-evenkit-tca-design-system-adaptation.md)  
**Recipe:** `~/Desktop/Personal/recipes/ios-tca-kit.md`

## Global Constraints

- Package name `EvenKit`; app target `Even` (never same name).
- Product Features follow `even-design-system/` only — no Money / Reset Feature without a design file.
- Features import Client interfaces, never `*ClientLive`.
- Live clients use shared API/session instances, not throwaways.
- Reducers never take a MainActor hub as `@Dependency`.
- Phase 2 Features: working navigation + clients; rough UI OK.
- Phase 3: refine each Feature to its `.dc.html` one by one.
- **Design owns the shared primitive catalog** (recipe §3); Features compose it —
  no parallel button/field/list kits.
- Contract-first: API shape changes update `docs/product/API.md` + `backend/internal/api/router.go`.
- Defer heavy `swift test` / xcodebuild / UITest loops until Feature wiring needs it; don’t block scaffolding on green CI.
- Do not commit unless the user asks.

---

## File structure (end state)

```
Package.swift                          # name: EvenKit; TCA + Dependencies pins
Sources/Core/                          # models, Keychain, WidgetSnapshot, pure planners
Sources/Design/                        # tokens + shared UI primitives (grow catalog; recipe §3)
Sources/AuthClient/ + AuthClientLive/
Sources/HouseholdClient/ + HouseholdClientLive/
Sources/GoogleClient/ + GoogleClientLive/
Sources/DraftsClient/ + DraftsClientLive/
Sources/TasksClient/ + TasksClientLive/
Sources/CalendarClient/ + CalendarClientLive/
Sources/SummaryClient/ + SummaryClientLive/
Sources/NotificationsClient/ + NotificationsClientLive/
Sources/WidgetClient/ + WidgetClientLive/
Sources/DI/ClientRegistration.swift
Sources/OnboardingFeature/
Sources/HouseholdSetupFeature/
Sources/ConnectionsFeature/
Sources/InboxFeature/
Sources/TodayFeature/
Sources/EvenApp/                       # AppReducer + EvenRootView wiring
Sources/HouseholdCore/                 # unchanged
Sources/HouseholdCommandCenter/        # mac shell, unchanged deps
ios/project.yml                        # package EvenKit; app → EvenApp + DI
ios/EvenApp/EvenApp.swift              # @main → EvenKit root
ios/EvenWidgets/                       # iPhone WidgetKit
ios/EvenWatch/                         # watchOS app shell (scaffold)
ios/EvenWatchWidgets/                  # Watch WidgetKit (scaffold)
docs/ARCHITECTURE.md
even-design-system/                    # visual contract (reference only)
```

**Extension rule:** Watch + both widget targets depend on `EvenCore` (and Design
tokens if needed) only — no Feature stores, no `*ClientLive`.


Transitional (delete by Slice 5): `Sources/EvenMobile/AppModel.swift`, `Sources/EvenCore/SessionStore.swift`, fat `EvenMobile` product.

---

### Task 0: Slice 0 — EvenKit scaffold + pure-TCA boot bridge

**Files:**
- Modify: `Package.swift`
- Modify: `ios/project.yml`
- Create: `Sources/Core/` (move from `Sources/EvenCore/` or re-export path)
- Create: `Sources/Design/` (tokens from `docs/design/README.md` / design system;
  stub folder grammar for shared primitives — Buttons/FormFields/… — without
  inventing a parallel vocabulary; full catalog lands in later Design slice work)
- Create: `Sources/AuthClient/AuthClient.swift`, `Sources/AuthClientLive/AuthClientLive.swift`
- Create: `Sources/DI/ClientRegistration.swift`
- Create: `Sources/EvenApp/AppReducer.swift`, `Sources/EvenApp/EvenRootView.swift`
- Create: `docs/ARCHITECTURE.md`
- Modify: `CLAUDE.md`, `AGENTS.md` (package paths)
- Test: `Tests/CoreTests/` (rename/migrate `EvenCoreTests`)
- Test: `Tests/EvenAppTests/AppReducerTests.swift`

**Interfaces:**
- Consumes: existing `EvenAPIClient`, Keychain session, `MeResponse`
- Produces:
  - `AppReducer.State`: `enum { case booting; case legacyReady; /* later: onboarding, ready */ }`
  - `AuthClient` with bootstrap/signOut endpoints (async)
  - Package product(s) so `ios/Even` links and launches

- [x] **Step 1: Pin dependencies and rename package**

In `Package.swift`: set `name: "EvenKit"`. Add package deps for `ComposableArchitecture` and `swift-dependencies` (current stable tags). Keep `HouseholdCore` / mac targets compiling.

- [x] **Step 2: Introduce `Core` + `Design` targets**

Move or alias `Sources/EvenCore` → `Sources/Core` (or path: `Sources/Core` copying files). Add `Design` with color/type tokens **and** a folder stub for upcoming primitives (`Tokens/`, later `Buttons/`, `FormFields/`, `Table/`, … — Personal recipe §3). Do not invent Feature-local button/field kits. Keep a temporary `EvenCore` product that equals `Core` if widgets/xcodegen need a soft rename — prefer one cut: widgets depend on `Core`.

- [x] **Step 3: Add AuthClient interface + Live + DI**

```swift
@DependencyClient
public struct AuthClient: Sendable {
  public var bootstrap: @Sendable () async -> AuthBootstrapResult = { .signedOut }
  public var signOut: @Sendable () async -> Void = { }
}
```

Live wraps existing Keychain + GoTrue + `me()`. `DI` `@_exported import AuthClientLive`.

- [x] **Step 4: Write failing `AppReducer` boot test**

```swift
@Test @MainActor
func bootTransitionsToLegacyReadyWhenSessionReady() async {
  let store = TestStore(initialState: AppReducer.State.booting) {
    AppReducer()
  } withDependencies: {
    $0.authClient.bootstrap = { .ready(/* minimal me */) }
  }
  await store.send(.appStarted)
  await store.receive(\.bootstrapResponse.ready) {
    $0 = .legacyReady
  }
}
```

(Adapt to project’s XCTest vs Swift Testing — match existing suite style or introduce Swift Testing in this target only.)

- [x] **Step 5: Implement `AppReducer` + wire `@main`**

Root view: `.booting` → splash (from Onboarding design splash tokens); `.legacyReady` → existing `MainScaffold` / onboarding via thin adapter that still uses old `SessionStore`+`AppModel` **only inside legacy**. New code path must not grow `AppModel`.

- [x] **Step 6: Update xcodegen + project.yml**

`ios/project.yml` package name `EvenKit`; app depends on `EvenApp` + `DI`; widgets on `Core`. Run `cd ios && xcodegen generate`. Build scheme **Even** for iPhone simulator.

- [x] **Step 7: Write `docs/ARCHITECTURE.md` + update agent guides**

Copy doctrines from spec §9. Point CLAUDE.md at EvenKit / Features.

- [x] **Step 8: Verify**

```bash
swift test
cd ios && xcodegen generate
xcodebuild -project Even.xcodeproj -scheme Even -destination 'platform=iOS Simulator,name=iPhone 16' build
```

- [ ] **Step 9: Commit** (only if user asks)

```
refactor(ios): rename package to EvenKit and add TCA AppReducer boot bridge
```

---

### Task 1: Slice 1 — OnboardingFeature (design 01)

**Files:**
- Create: `Sources/OnboardingFeature/**` (Reducer, Views per screen, PreviewSupport, DemoHooks)
- Modify: `Sources/EvenApp/AppReducer.swift` — add `.onboarding` case; leave `.legacyReady` for post-auth
- Reference: `even-design-system/Onboarding.dc.html`
- Test: `Tests/OnboardingFeatureTests/`

**Interfaces:**
- Consumes: `AuthClient` (sign-in with Apple / debug email)
- Produces: `OnboardingFeature.Action.delegate` → `.signedIn` / `.finishedHowItWorks` into AppReducer

- [x] **Step 1: Write failing TestStore for welcome → how-it-works progression**
- [x] **Step 2: Implement reducer + views 1:1 with design screens (Splash, Welcome, How it works 1–3)**
- [x] **Step 3: Wire AppReducer path; EvenMobile (incl. OnboardingViews) deleted**
- [x] **Step 4: Previews via PreviewSupport; run feature tests + app build**
- [ ] **Step 5: Commit** (if asked): `feat(ios): OnboardingFeature from design system flow 01`

---

### Task 2: Slice 2 — HouseholdSetupFeature (design 02)

**Files:**
- Create: `Sources/HouseholdClient/`, `HouseholdClientLive/`, `Sources/HouseholdSetupFeature/**`
- Reference: `even-design-system/Household Setup.dc.html`
- Test: `Tests/HouseholdSetupFeatureTests/`

**Interfaces:**
- Consumes: `HouseholdClient.create`, `.join`, invite polling as needed
- Produces: delegate `.householdReady` → AppReducer advances to Connections or legacy

- [x] **Step 1: HouseholdClient interface + Live (wrap existing API create/join)**
- [x] **Step 2: Failing tests for create path, join error, partner-joined**
- [x] **Step 3: Implement screens 1:1 (path choice, name, invite, join, waiting, joined)**
- [x] **Step 4: Wire into onboarding stack; remove replaced legacy household UI**
- [x] **Step 5: Verify** (commit only if asked)

---

### Task 3: Slice 3 — ConnectionsFeature (design 03)

**Files:**
- Create: `Sources/GoogleClient/`, `GoogleClientLive/`, `Sources/ConnectionsFeature/**`
- Move OAuth presentation out of `GoogleConnectViews.swift` into Live/client bridge
- Reference: `even-design-system/Email & Calendar Setup.dc.html`
- Test: `Tests/ConnectionsFeatureTests/`

**Interfaces:**
- Consumes: `GoogleClient.connect`, `.status`, `.startSync`
- Produces: delegate `.connectionsComplete` / skip

- [x] **Step 1: GoogleClient with async connect (ASWebAuthenticationSession behind Live)**
- [x] **Step 2: Failing tests for connect success / skip / connections settings**
- [x] **Step 3: UI 1:1 from design; quarantine `--skip-google-prompt` in DemoHooks**
- [x] **Step 4: Wire stack; delete old Google connect extras path as replaced**
- [x] **Step 5: Verify** (commit only if asked)

---

### Task 4: Slice 4 — InboxFeature (design 04)

**Files:**
- Create: Drafts/Calendar/Notifications clients + Live; `Sources/InboxFeature/**`
- Reference: `even-design-system/Email Ingestion.dc.html`
- Retire: legacy `InboxView` draft sheets ownership; pull review UI into Feature
- Test: `Tests/InboxFeatureTests/`

**Interfaces:**
- Consumes: `DraftsClient`, `CalendarClient`, `NotificationsClient`
- Produces: `MainState.inbox` scoped child; `@Presents` review sheet

- [x] **Step 1: Client interfaces + Live for drafts/calendar/notifications**
- [x] **Step 2: TestStore — load pending, approve → stamp/calendar effect, dismiss, empty state**
- [x] **Step 3: Build Approval Inbox + review sheet + calendar screens per design**
- [x] **Step 4: Introduce `.ready` MainState with Inbox tab/destination; shrink `.legacyReady`**
- [x] **Step 5: Update UITests selectors for Approval Inbox**
- [x] **Step 6: Verify** (commit only if asked)

---

### Task 5: Slice 5 — TodayFeature + remove legacy hub (design 05)

**Files:**
- Create: Tasks/Summary/Widget clients + Live; `Sources/TodayFeature/**` (incl. BeamPhysics move)
- Modify: `AppReducer` — remove `.legacyReady`; ready = Inbox + Today only
- Delete: `AppModel.swift`, `SessionStore.swift`, dead Money/Reset tab wiring from main chrome
- Reference: `even-design-system/Todo Creation.dc.html`
- Test: `Tests/TodayFeatureTests/`

**Interfaces:**
- Consumes: `TasksClient`, `SummaryClient`, `WidgetClient`
- Produces: Today list + `@Presents` new/edit todo; beam view reads summary weights

- [x] **Step 1: Clients + failing tests for add todo, toggle, edit/delete, summary refresh**
- [x] **Step 2: Today UI 1:1 (empty, interactive, pebble drop, edit sheet)**
- [x] **Step 3: Port BeamPhysics as view island; feed state from summary**
- [x] **Step 4: Remove `.legacyReady` from app boot; SessionStore retained for Live clients; EvenMobile unlinked**
- [x] **Step 5: Widgets still publish via WidgetClient after mutations**
- [x] **Step 6: Full Feature builds + UITests retargeted + Even build**
- [ ] **Step 7: Commit** (if asked): `feat(ios): TodayFeature and remove AppModel hub`

---

### Task 6: Cleanup & docs freeze

**Files:**
- Modify: `docs/product/PRD.md` (design source → `even-design-system/` + Features)
- Modify: `CLAUDE.md` structure section
- Remove empty transitional `EvenMobile` / `EvenCore` products if still present
- Optional: `scripts/build-module.sh` from recipe

- [x] **Step 1: Grep for AppModel, SessionStore, EvenMobile leftovers — delete or re-export cleanly**
- [x] **Step 2: Confirm Money/Reset not reachable from main chrome**
- [x] **Step 3: ARCHITECTURE.md + PRD + CLAUDE.md match reality**
- [x] **Step 4: Final verify**

```bash
swift test
cd ios && xcodegen generate
# build Even + run EvenUITests smoke if backend up
```

- [ ] **Step 5: Commit** (if asked): `docs(ios): freeze EvenKit TCA + design-system architecture`

---

## Execution notes

- Prefer **subagent-driven-development** one Task at a time; keep `main` green after each Task.
- Do not start Slice N+1 until Slice N builds and its Feature tests pass.
- When a design screen needs API behavior the backend lacks, stop and update `API.md` + backend in that same slice — do not fake product behavior only in the client.
- Preview design files via local HTTP (`python3 -m http.server` in `even-design-system/`), not `file://`.
