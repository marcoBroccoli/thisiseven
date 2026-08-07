# Profile tab — design

## Goal

Add a third main tab for **basic profile management**: identity (editable
display name + clay/teal color), household info, Google Connections manage,
and Sign out. Today’s tab icon becomes home.

## Decision

| Choice | Decision |
|---|---|
| Surface | Full tab (not a sheet) — Today · Inbox · Profile |
| Module | New SPM Feature `ProfileFeature` |
| Approach | Feature + `PATCH /v1/me` (persist name/color) |
| Icons | Today `house`, Inbox `tray`, Profile `person.crop.circle` |
| Connections | Reuse `ConnectionsReducer` settings path inside Profile |
| Out of v1 | Leave household, delete account, edit household name, show Apple email |

## Tabs & shell

- `MainTabReducer.State.Tab`: `.today` \| `.inbox` \| `.profile` (`CaseIterable` order = bar order)
- `MainTabView`: third `Tab` hosting `ProfileView`; pass `$tabBarProgress`
- `IGStyleTabBar` item map updated for the three symbols
- Profile scrolls with `.adoptForIGTabBar` (same collapse as Today/Inbox)

## Profile screen

Paper + `NavigationStack` chrome (`.evenPaperNavigationChrome()` / brand
principal as Inbox). Single-screen Feature — body on `ProfileView`; atoms in
`Components/`.

Sections (top → bottom):

1. **You** — initial avatar tinted by member color; text field for display name;
   color swatches + system ColorPicker (any `#RRGGBB`). Save on commit / color
   change via PATCH; optimistic UI with toast on failure + revert.
2. **Household** — household name; partner row (name + color, read-only);
   invite code with copy-to-clipboard.
3. **Connections** — scoped `ConnectionsReducer` in settings/manage mode
   (existing `ConnectionsSettingsView` pattern: status, scope toggles,
   disconnect). Not the setup path.
4. **Account** — Sign out button → confirmation alert → `AuthClient.signOut`
   (app returns to Login via existing session phase).

## API

```
PATCH /v1/me
{ "display_name"?: string, "color"?: "#RRGGBB" }
→ member
```

Rules:

- Requires auth + household membership (same gate as other `/v1/*` data routes).
- At least one field required; empty body → 400.
- `display_name`: trim; reject empty / overlong (cap 40).
- `color`: any `#RRGGBB` (legacy `clay`|`teal` normalized). Partners may share
  a color. Migration `010_member_color_hex` drops the clay/teal check + unique.
- Contract: update `docs/product/API.md` and `backend/internal/api/router.go`
  together. Handler lives with household/me code.

## Client seams

- `EvenAPIClient.patchMe(displayName:color:)` (+ existing `me()`).
- Extend `HouseholdClient` with:
  - `loadProfile: () async throws -> MeResponse`
  - `updateMe: (displayName: String?, color: MemberColor?) async throws -> Member`
- Live implementations call the API and refresh `SharedSession` so Today owner
  labels and beam stay consistent after edit.
- `AuthClient.signOut` unchanged.
- Toasts via existing app-level `.evenToastHost()` (MainTab / root); Profile
  only sends through `ToastClient`.

## Module layout

```
Sources/Feature/ProfileFeature/
  ProfileReducer.swift
  ProfileView.swift          # #if os(iOS)
  Watch/ProfileView+Watch.swift
  Components/…               # section rows, color control, skeleton
  Preview/PreviewSupport.swift
Tests/ProfileFeatureTests/
```

`Package.swift`: product + target (deps: EvenCore, Design, TCA, AuthClient,
HouseholdClient, ConnectionsFeature, ToastClient, IGTabBar iOS-only). Wire into
`EvenApp` / `MainTab`. Add test target to `EvenKitTests` scheme.

## Errors & empty states

| Case | Behavior |
|---|---|
| First load | Skeleton (`isLoading` true until profile lands) |
| Re-appear with data | No skeleton flash |
| Load / PATCH fail | Toast; keep last good state; revert optimistic edit |
| Empty display name | Inline validation; no network call |
| Sign out | Confirm alert; then sign out |

## Tests

- **Go:** PATCH name; PATCH color with partner swap; empty name 400; anon 401.
- **TCA:** appear loads profile; save name; select color; sign out sends
  `AuthClient.signOut`.
- **MainTab:** three tabs; `selectTab(.profile)`.

## Non-goals (explicit)

- Leave / dissolve household
- Delete account
- Edit household name
- Profile photo
- Push notification prefs
