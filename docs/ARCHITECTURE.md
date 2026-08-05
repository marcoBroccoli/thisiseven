# Even — Apple platforms architecture

Distilled from `~/Desktop/Personal/recipes/ios-tca-kit.md` and
`docs/superpowers/specs/2026-08-05-evenkit-tca-design-system-adaptation.md`.

## One sentence

**SPM package `EvenKit` = product brain. Xcode `Even` = Apple shell (iPhone app +
Watch app + iPhone widgets + Watch widgets). Features own screens. Clients own
side effects. EvenCore owns truth models. Design owns tokens and shared UI
primitives. `DI` wires Live clients.**

Open **`Even.xcworkspace`** (only the `.xcodeproj`).

## Package folder grammar (not separate packages)

```
Sources/
  Core/       # EvenCore, *Client, *ClientLive, DI
  Feature/    # *Feature, EvenApp
  Design/     # Design target root (tokens + primitives)
```

One `Package.swift`. Targets keep their names; only **paths** are layered.

## Platforms

| Surface | Min OS | Notes |
|---|---|---|
| iPhone app (`Even`) | **iOS 18+** | Pure TCA root; design-system Features |
| iPhone widgets | iOS 18+ | WidgetKit; `EvenCore` snapshots / App Group |
| watchOS app | **watchOS 11+** | Companion; thin shell on Core |
| Watch widgets | watchOS 11+ | WidgetKit on watch |

No macOS app. Build/test via Xcode / `xcodebuild`.

## Doctrines

1. One authority for domain numbers (summary % from clients).
2. Features import Client interfaces, never Live.
3. Live uses shared instances (`SharedSession`, shared API).
4. Reducers don’t depend on a MainActor hub.
5. Previews from catalogs; demo hooks quarantined.
6. Package `EvenKit` ≠ app `Even`; workspace = single xcodeproj.
7. Product Features follow `docs/even-design-system/`.
8. Contract-first API docs.
9. Design owns primitives; Features compose them.
10. Extensions stay thin — Core (+ Design tokens), no Feature stores / Live.
11. **Every `*View` has `#Preview` in the same file.** Mocks are centralized:
    `EvenCore/PreviewData` (domain), `Design/PreviewSupport` (chrome),
    `*Feature/PreviewSupport` (Store factories), `EvenApp/PreviewSupport` (root).

## Boot path

`.booting` → `.onboarding` / `.householdSetup` / `.connections` / `.ready(MainReducer)`  
Main chrome: **Today** + **Inbox** only. Money / Weekly Reset deferred until designed.

## Current state

- Feature path is the only app boot path.
- Clients Live: Auth, Household, Google, Drafts, Tasks, Summary, Calendar, Widget, Notifications.
- Today: summary list + `BeamScaleView` + composer sheet.
- Inbox: approval list + review sheet + shared calendar surface.
- Non-app resources live under `docs/` (design-system, web, promo, supabase stubs).
- Legacy `EvenMobile` / `HouseholdCore` / mac app removed.
