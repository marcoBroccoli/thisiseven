# EvenKit + TCA + design-system adaptation

**Date:** 2026-08-05  
**Status:** approved for planning (conversation decisions locked)  
**Recipe:** `~/Desktop/Personal/recipes/ios-tca-kit.md`  
**Design source of truth:** `even-design-system/` (Index + five flow `.dc.html` files)

---

## 1. Intent

Fully adapt the Personal **iOS TCA kit** into thisiseven, and rebuild the iOS product surface to match the **new MVP design system**. The design flows define which Features exist — not the current Today / Todos / Schedule / Money tab set.

Decisions locked:

| Decision | Choice |
|---|---|
| Scope | Full restructure (all Features + clients + root `AppReducer`) |
| Session / auth | Pure TCA — root owns `.booting \| .onboarding \| .ready` |
| Package | Rename SPM to **`EvenKit`**; keep `HouseholdCore` / mac in same package |
| Landing | Vertical slices on `main`, each slice green |
| Delivery | **Unfinished-app phases:** (1) scaffold → (2) Feature shells + rough wiring → (3) refine UI to `.dc.html` one by one |
| Platforms | **iOS 18+** iPhone app + widgets; **watchOS 11+** Watch app + Watch widgets; latest TCA / Apple SDK |
| Feature map | The five design flows (Approach 1) |

---

## 2. Product surface (from design)

Source: `even-design-system/Index.dc.html`.

| # | Design flow | File | Product meaning |
|---|---|---|---|
| 01 | Onboarding | `Onboarding.dc.html` | Splash → welcome/sign-in → how-it-works (3) |
| 02 | Household Setup | `Household Setup.dc.html` | Create/join, invite code, waiting, partner joined |
| 03 | Email & Calendar Setup | `Email & Calendar Setup.dc.html` | Connect Gmail/Calendar + Connections settings |
| 04 | Ingestion & Reminders | `Email Ingestion.dc.html` | Approval Inbox, review, calendar event, notifs, month |
| 05 | Todo Creation | `Todo Creation.dc.html` | Today + beam + new/edit todo sheets |

**Not in MVP design (deferred):** Money tab, Weekly Reset UI, old multi-filter Todos chrome. Keep API DTOs in `Core` if useful; no Feature until a design file exists.

**Main chrome after ready:** driven by flows 04–05 (Inbox + Today; Calendar appears inside ingestion design — treat as tab or nested destination as screens require, not as the old four-tab shell).

---

## 3. Architecture

### One-sentence (recipe)

**SPM package = product brain. Xcode project = Apple shell (app + widgets). Features own screens. Clients own side effects. Core owns truth models. Design owns tokens + shared UI primitives. One composition root wires Live clients.**

### Pure TCA root

```text
AppReducer.State =
  .booting
  | .onboarding(OnboardingPath)   // flows 01 → 03
  | .ready(MainState)             // Inbox + Today (+ Calendar destination)
  | .legacyReady                  // temporary bridge only during early slices
```

- No long-lived `SessionStore` / `AppModel` hub after cutover.
- Auth is `AuthClient`. Household is `HouseholdClient`. Effects never construct services ad hoc.
- Reducers do not take MainActor hubs as `@Dependency`. MainActor OS work is exposed as **async** client endpoints.

### SPM Feature ↔ design flow

| Feature target | Design | Child patterns |
|---|---|---|
| `OnboardingFeature` | 01 | Tab-resident / stack steps |
| `HouseholdSetupFeature` | 02 | Stack + error states |
| `ConnectionsFeature` | 03 | Stack + `@Presents` for OAuth / settings |
| `InboxFeature` | 04 | List + `@Presents` review sheet; calendar surfaces |
| `TodayFeature` | 05 | List + `@Presents` new/edit todo; SpriteKit beam as UI island |

### Layer map

```
Even (ios shell) + DI (*ClientLive)
        │
        ▼
   *Feature  ──►  *Client (interface)  ──►  Core
        │
        └──►  Design ──► Core

Widgets extension ──► Core only
```

| Layer | May depend on | Must not |
|---|---|---|
| `Core` | Foundation (mostly) | UI, Features, Clients, Services |
| `Design` | Core (pure types only) | Features, domain Clients |
| `*Client` | Core, Dependencies | Live, Features, UI |
| `*ClientLive` | Client + Core services | Features |
| `*Feature` | Core, Design, Client interfaces, TCA | `*ClientLive`, app shell |
| App shell | Everything + `DI` | — |

Sibling Features: avoid unless product-true. Prefer SharedUI only when two Features need the same *composed* view. **Primitives** (buttons, fields, list rows, tags, chrome) live in `Design`, not SharedUI — see Personal recipe §3.

---

## 4. Package / workspace

### Rename

- Today: package name `HouseholdCommandCenter`, products `EvenCore` / `EvenMobile`.
- Target: package name **`EvenKit`**, app target remains **`Even`**.
- Keep products: `HouseholdCore`, mac executable `HouseholdCommandCenter`.

### Suggested targets (iOS path)

```
Sources/
  Core/                    # was EvenCore models + pure helpers + WidgetSnapshot
  Design/                  # tokens + shared UI primitives (see §6)
  AuthClient/ + AuthClientLive/
  HouseholdClient/ + HouseholdClientLive/
  GoogleClient/ + GoogleClientLive/
  DraftsClient/ + DraftsClientLive/
  TasksClient/ + TasksClientLive/
  CalendarClient/ + CalendarClientLive/
  SummaryClient/ + SummaryClientLive/
  NotificationsClient/ + NotificationsClientLive/
  WidgetClient/ + WidgetClientLive/
  DI/                      # ClientRegistration @_exported Live imports
  OnboardingFeature/
  HouseholdSetupFeature/
  ConnectionsFeature/
  InboxFeature/
  TodayFeature/
  EvenApp/                 # AppReducer, root view wiring (or Sources/Even/)
  HouseholdCore/           # unchanged mac domain
  HouseholdCommandCenter/  # mac shell
```

During migration, `EvenMobile` / `EvenCore` may remain as transitional products that re-export or host legacy UI until each slice deletes its path. End state: no `AppModel`, no `SessionStore`, no fat `EvenMobile` god target.

### Workspace rules (recipe)

1. Package name ≠ app name (`EvenKit` ≠ `Even`).
2. Workspace lists only the `.xcodeproj`.
3. Local package linked from Xcode / xcodegen.
4. One DerivedData path per intentional build; sequential module builds.
5. iPhone + portrait stays in project settings / xcconfig.

### Third-party pins

- `ComposableArchitecture` (TCA)
- `swift-dependencies` / `DependenciesMacros` on Client interfaces  
Features depend on TCA; Client interfaces depend on Dependencies only.

### xcodegen

Update `ios/project.yml`:

- Package path/name → `EvenKit`
- App depends on shell product + `DI` (Live linkage)
- Widgets depend on `Core` only
- Regenerate: `cd ios && xcodegen generate`

---

## 5. Clients

Split by domain (not one god client). Live values resolve through **shared** `EvenAPIClient` / Keychain / OS wrappers.

| Client | Responsibility |
|---|---|
| `AuthClient` | Sign-in, refresh, Keychain session, bootstrap `me` |
| `HouseholdClient` | Create / join household |
| `GoogleClient` | PKCE OAuth presentation bridge + status / sync start |
| `DraftsClient` | Pending list, patch, approve, dismiss, propose |
| `TasksClient` | CRUD, toggle, calendar resolve |
| `CalendarClient` | Dated window, sync, calendar info / share URL |
| `SummaryClient` | Week summary (beam %) |
| `NotificationsClient` | Permission + schedule/cancel reminders |
| `WidgetClient` | Publish App Group `WidgetSnapshot` |

Money / reset / appreciation / trade endpoints: keep on a dormant helper or `MoneyClient` with no Feature until designed. Do not wire into `AppReducer`.

**Interface pattern:** `@DependencyClient` + explicit `testValue` + `DependencyValues` key.  
**Live pattern:** `DependencyKey.liveValue` calling shared instances; MainActor touchpoints are `async`.

---

## 6. Design system

- `Design` target owns tokens extracted from Even Play / MVP flows: paper `#E9E1D2` / `#F6F1E6`, espresso `#26201A`, terracotta `#A6552F` / `#A0522D`, pine `#37756D`, Newsreader + Source Sans 3.
- **Primitive pattern (mandatory):** one shared Design component catalog for the
  app. Features compose it; they do not invent parallel button / field / list kits.
  Full layering, categories, and dependency rules: Personal recipe
  `~/Desktop/Personal/recipes/ios-tca-kit.md` §3.
  - Layering: core tokens/fonts/assets → SwiftUI bridges → primitive components
    (Buttons, FormFields, Controls, Tags&Pills, Table/ListItem, Navigation chrome,
    NotificationToast, Placeholder, typography helpers).
  - Day-1 EvenKit may keep a single `Design` target; grow folder grammar + split
    products as the catalog grows.
  - Keep Design free of domain `*Client`s. Features pass bindings/actions.
- Screen layouts and copy follow the corresponding `.dc.html` 1:1 for each Feature slice.
- `even-design-system/` stays in-repo as the visual contract (Claude Design runtime; needs `support.js` + HTTP to preview).
- SpriteKit beam (`BeamPhysics`) lives under `TodayFeature` as a view island: feed owner weights / completion in; do not put physics ticks in the reducer.
- Google OAuth / `ASWebAuthenticationSession` stays behind `GoogleClient` (UIKit presentation bridge).

---

## 7. Slice plan (vertical, on `main`)

Each slice: design UI + TCA Feature + client(s) + tests; delete the legacy path it replaces; app remains bootable.

| Slice | Deliverable |
|---|---|
| **0** | EvenKit rename scaffolding; `Core` + `Design` + `DI` + `AuthClient`; `AppReducer` with `.booting` + temporary `.legacyReady` wrapping current main/onboarding until replaced |
| **1** | `OnboardingFeature` from `Onboarding.dc.html`; AuthClient wired; remove old welcome/how-it-works path |
| **2** | `HouseholdSetupFeature` from `Household Setup.dc.html`; HouseholdClient |
| **3** | `ConnectionsFeature` from `Email & Calendar Setup.dc.html`; GoogleClient |
| **4** | `InboxFeature` from `Email Ingestion.dc.html`; Drafts + Calendar + Notifications clients; replace legacy inbox/draft sheets |
| **5** | `TodayFeature` from `Todo Creation.dc.html`; Tasks + Summary + Widget clients; remove `AppModel` / `.legacyReady` |

**Exit criteria for “done”:** pure TCA root only; no `AppModel` / `SessionStore`; tabs/chrome match design IA; `swift test` + UITests updated for new selectors; widgets still publish snapshots.

---

## 8. Testing & demos

- **Unit:** `TestStore` per Feature; client `testValue` / overrides for effects.
- **Core:** keep pure DTO / planning tests (migrate `EvenCoreTests` → `CoreTests`).
- **Previews:** every `*View` has `#Preview` in-file. Mocks centralized —
  `EvenCore/PreviewData` (domain), `Design/PreviewSupport` (chrome),
  `*Feature/PreviewSupport` (stores), `EvenApp/PreviewSupport` (root). No inline fixtures.
- **DemoHooks:** quarantine launch-arg hooks (`--skip-google-prompt`, `--reset-session`) in `DemoHooks*Feature` / app shell — no scattered `#if DEBUG` in views.
- **UITests:** retarget to Inbox / Today / onboarding flows; update per slice, not only at the end.

---

## 9. Docs & doctrines

Add `docs/ARCHITECTURE.md` (trimmed recipe doctrines):

1. One authority for domain numbers (summary % from `SummaryClient`, not recomputed in views).
2. Features import Client interfaces, never Live.
3. Live uses shared instances.
4. Reducers don’t depend on a MainActor hub.
5. Previews show real mocked UI; data from catalogs.
6. Demo/e2e code is quarantined.
7. Package name ≠ app name; workspace = single xcodeproj.
8. Sequential module builds; don’t fight DerivedData.
9. Product Features follow `even-design-system/` — not legacy tab names.
10. Contract-first: API changes still update `docs/product/API.md` + `router.go`.
11. Design owns shared UI primitives; Features compose them (Personal recipe §3).

Update `CLAUDE.md` / `AGENTS.md` paths when EvenKit rename lands (Slice 0).

---

## 10. Non-goals

- Implementing Money / Weekly Reset without a design file.
- Offline local-first task cache (mobile remains fetch + optimistic patch + re-fetch unless separately specified).
- TCA inside WidgetKit extension.
- Big-bang long-lived branch; cargo-culting Kilo module names.
- Changing backend contract unless a design flow requires it (call out in the Feature slice).

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| Package rename breaks xcodegen / CI | Slice 0 is rename + green build only |
| UITests brittle during IA change | Update selectors per slice; keep `--skip-google-prompt` |
| OAuth UIKit bridge in TCA | Isolate in `GoogleClient`; Feature only sends intents |
| Beam physics complexity | Keep SpriteKit outside reducers |
| Scope creep (Money, mac) | Explicit deferral; mac/`HouseholdCore` untouched except package name |

---

## 12. Self-review

- No TBD placeholders for locked decisions.
- Feature map matches Index (five flows); Money deferred consistently.
- Pure TCA vs hybrid: pure root; temporary `.legacyReady` only for strangler.
- Slice order matches design reading order.
- Client list covers side effects used by those flows (auth, household, google, drafts, tasks, calendar, summary, notifications, widgets).
