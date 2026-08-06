# thisiseven — agent guide

**Even** — "Money, settled weekly." A **Household Command Center** for a couple
(Umur + Beste): shared chores/todos, a weekly settle-up (who did what, the
fair split), household money (expenses → settlements), an email→task inbox, and
two-way Google Calendar sync. Domain: **thisiseven.app** (Cloudflare).

iOS-first (SwiftUI) + Watch/widgets, a Go backend (`evend`), Postgres + GoTrue
for auth. No shipping macOS app — product surfaces are iPhone + Watch only.

> Read `docs/product/API.md` before touching the backend or the mobile client —
> it is the **contract source of truth** for every endpoint and data shape.

## Project structure — what does what

### `backend/` — the evend Go API (all app data lives here)
- `cmd/evend/main.go` — entrypoint. On startup it **auto-runs embedded SQL
  migrations** (`migrations/*.sql`, applied in filename order, tracked in the
  `schema_migrations` table — no framework). Restarting the service applies any
  new migration.
- `cmd/evend/migrations/` — schema history `001`→`008`. Latest:
  `006_calendar_sync`, `007_draft_replies`, `008_recurring_occurrences`
  (daily / every-2-day chores record one completion **per occurrence** in
  `recurring_completions`; weekly + one-off stay in `completions`).
- `internal/api/` — HTTP handlers, wired in `router.go` (mirror it to `API.md`):
  - `tasks.go` — household chores/todos: CRUD, toggle (open-week completion),
    recurrence, and `…/calendar/resolve` (acknowledge/restore/retry a Calendar edit).
  - `calendar.go` + `calendar_sync.go` — dated-todo window + `POST /v1/calendar/sync`
    (two-way reconcile of the **dedicated shared household calendar** only).
  - `drafts.go` — email→task inbox drafts + the Gmail **reply** workflow
    (Claude-suggested reply; the app opens Gmail compose, never sends via API).
  - `money.go` — expenses, settlements, appreciations, trades.
  - `households.go` — household, members, invite codes.
  - `summary.go` — the week summary (percent split, sectioned task list, caption).
  - `store.go` — DB access helpers · `types.go` — API DTOs · `reset.go` — dev reset.
- `internal/google/` — minimal Gmail + Calendar client (refresh-token OAuth,
  message listing/metadata, all-day + RRULE calendar writes); `extract.go` parses
  messages. `ErrNotConfigured` when `GOOGLE_OAUTH_CLIENT_ID/SECRET` are absent.
- `internal/claude/` — Claude client (reply suggestions / extraction).
- `internal/auth/` — Bearer access verification (GoTrue) · `internal/httpx/` —
  middleware (recover, logging, access verifier) · `internal/config/` — env config.

### `Sources/` — EvenKit SPM targets (one package; folder layers only)
Package name **EvenKit**. Open via **`Even.xcworkspace`** (lists `ios/Even.xcodeproj`
only — never also open `Package.swift` as a sibling workspace item).

Layer folders (not separate packages):

```
Sources/
  Core/       # EvenCore, *Client, *ClientLive, DI
  Feature/    # *Feature, EvenApp
  Design/     # tokens + shared UI primitives
  Shared/     # portable UI kits (ToastUI, …) — no Even tokens
```

- `Core/EvenCore/` — API client, GoTrue auth, Keychain, shared models,
  `SharedSession` (Live clients only).
- `Core/*Client` + `*ClientLive` + `DI/` — dependency clients; Features import
  interfaces only; app links `DI` for Live.
- `Feature/EvenApp/` — TCA `AppReducer` + `EvenAppRootView` (boot → onboarding
  stack → Today + Inbox).
- `Feature/{Onboarding,HouseholdSetup,Connections,Inbox,Today}Feature/` —
  product Features mapped to `docs/even-design-system/`.
- `Design/` — design tokens (paper / espresso / terracotta / pine) + primitives.
- Doctrines: `docs/ARCHITECTURE.md`. Visual contract: `docs/even-design-system/`.

### App shells & tests
- `ios/` — Apple shell: `Even.xcodeproj` (xcodegen from `project.yml`),
  `EvenApp/` (iPhone), `EvenWidgets/` (iPhone WidgetKit), `EvenWatch/` +
  `EvenWatchWidgets/` (watchOS 11+ scaffold), `EvenUITests/`. Product floors:
  **iOS 18+** / **watchOS 11+**. Build/test via Xcode / `xcodebuild`.
- `Tests/` — `EvenCoreTests`, `EvenAppTests`, and per-Feature TestStore suites.

### Docs & non-app resources (`docs/`)
See `docs/README.md`. Includes product docs, design-system HTML, promo JSON,
coming-soon web, supabase stubs, growth artefacts. Not part of the app binary.

## Data model (see `docs/product/API.md` for exact fields)
`household · member · week · task · draft · expense · settlement · appreciation ·
trade`. A **task** carries `section` (chore|admin), `weight` (1–3), `recurrence`
(none|daily|every_2_days|weekly), and calendar fields (`google_event_url`,
`calendar_sync_state`, last-synced/last-error). A **draft** carries the email
reply workflow (`needs_reply`, `suggested_reply`, `reply_status`).

## Commands
- Open app: `open Even.xcworkspace` (preferred) or `ios/Even.xcodeproj`.
- iOS app: `cd ios && xcodegen generate`, then build scheme **Even** for an iPhone sim;
  E2E: `xcodebuild … test` (EvenUITests — needs the backend stack up).
- Go tests: `docker run --rm -v "$PWD/backend":/src -w /src golang:1.24-alpine go test ./...`
  (no local Go toolchain on this box).
- Backend stack: `cd backend && docker compose up -d --build` (project `evend`:
  api `127.0.0.1:8091` + GoTrue + Postgres `5433`; Caddy route `http://even-api.home`).
- Stack secrets: `backend/.env` (gitignored) from `~/.env` `THISISEVEN_*` + `GOOGLE_OAUTH_*`.
- Deploy coming-soon page (Cloudflare Pages project `thisiseven`):
  ```bash
  cd docs/web/coming-soon && CLOUDFLARE_ACCOUNT_ID=64d6def322d7854f96a2460c2b1a88a4 \
    CLOUDFLARE_API_TOKEN=$CLOUDFLARE_PAGES_TOKEN \
    npx wrangler@4 pages deploy . --project-name=thisiseven --branch=main --commit-dirty=true
  ```
  (token in `~/.env`; domain + www attached to the Pages project, GSC verified —
  do NOT delete the google-site-verification TXT record on the zone.)

## Conventions
- **Local-first**: the on-device store (JSON / Keychain) is authoritative; Gmail
  and Calendar imports **MERGE**, never overwrite user-edited/approved items. A
  Calendar deletion becomes `external_deleted` (todo kept) until restored or archived.
- **Contract-first**: change `docs/product/API.md` alongside any endpoint change;
  `router.go` must match it.
- **Secrets** live in `~/.env` on the home server (and Keychain for OAuth tokens),
  never in the repo — reference them by NAME only.
- **Design language**: `docs/design/README.md` — cream paper / espresso ink /
  terracotta accent, Newsreader + Source Sans 3. Keep new UI on these tokens.
  Product Features follow `docs/even-design-system/`.
- Local git; the remote is `github.com/marcoBroccoli/thisiseven` (shared with
  Marco). No TestFlight/App Store distribution without Umur's explicit "ship it".

## SwiftUI chrome & paper (hard rules)

Learned from how-it-works / beam work — follow these on every Feature screen:

### Paper background
- Put `.evenPaperBackground()` on the **content inside** `NavigationStack` (see
  Inbox / Onboarding). A paper layer *behind* the stack is covered by the
  stack’s opaque chrome → looks like “no background” / flat white.
- Prefer **one** paper surface for a screen. Nested `EvenPaperBackground` under
  a clear nav bar misaligns grain vs the body.
- Horizontal/vertical `ScrollView` paints a system fill — use
  `.scrollContentBackground(.hidden)` or it covers paper.
- Root may also paint paper + `.evenGrainOverlay()`; don’t stack a second full
  grain tile on the same screen without checking the result.

### Navigation bar
- Keep the **system** bar. Compact page labels → `.inline` or
  `ToolbarItem(placement: .principal)` with the **app serif**, not a hand-rolled
  top HStack (e.g. no custom `← BACK` text headers — see Onboarding /
  HouseholdSetup).
- Clear the bar with `.toolbarBackground(.hidden)` /
  `.toolbarBackgroundVisibility(.hidden)` so paper shows through — don’t give
  the bar its own solid fill unless you intentionally want a different sheet.
- Back: prefer conditional `ToolbarItem` + `send(…, animation:)` over
  opacity-ghost buttons that stay in the toolbar when “hidden”.

### Controls on paper (disabled + hit targets)
- **Never** dim primary CTAs with view `.opacity` or rely on SwiftUI’s
  `.disabled` fade — grain/paper shows through and labels go muddy.
  `EvenPrimaryButton` uses a **solid** muted fill (`stone` when off) and
  `allowsHitTesting` instead of `.disabled` for the visual state.
- Card-style path buttons (Household choice rows) use `.buttonStyle(.plain)` —
  **always** add `.contentShape` on the full rounded rect so padding / empty
  space is tappable, not only the text glyphs.

### Multi-step Feature layout
- Peel into `Views/` only when the shell shows **more than one** distinct
  state/step (path switch). A single-screen Feature (e.g. Inbox / Today)
  stays inline on the main `*View` — don’t invent a one-file `Views/` wrapper.
- When multi-step: shell `*View` next to `*Reducer` owns `NavigationStack`,
  path switch, and shared chrome (error banner, **footer**, motion). Each
  step lives under `Views/` (`HouseholdChoiceView`, `ConnectionsWhyView`, …)
  sharing the same store — no per-step reducers unless the step earns its own
  Feature. Steps own **body content only**.
- Shared step typography / layout lives in a chrome helper
  (`HouseholdSetupChrome`, `ConnectionsSetupChrome`); atoms in `*Components`.
- Variable-width rows (invite code letter tiles) must **flex to the proposed
  width** — fixed tile sizes that exceed the content width widen the parent
  and clip leading copy off-screen.

### Shared footers (`safeAreaInset`) — always
- Portable doctrine (roles only): Personal recipe
  `~/Desktop/Personal/recipes/ios-tca-kit.md` → §4 “Sticky footers / flow CTAs”.
- Pin every setup / flow CTA strip with `.safeAreaInset(edge: .bottom)` on the
  **shell** (see `ConnectionsView` + `ConnectionsPathFooter`, Onboarding
  footer). Do **not** let each path view own its own footer tree.
- One persistent primary control + optional secondary. Path/state only remaps
  `State.footer` (title, style, enabled/busy, whether secondary exists) —
  `primaryTapped` / `secondaryTapped` route in the reducer by `path`.
- **Morph in place**, don’t replace: google outline → espresso fill must be
  the *same* button identity animating fill/stroke/icon/title
  (`ConnectionsFooterPrimaryButton`). Never `switch` between two different
  button view types on path change — that reads as a fade-out/replace.
- Secondary is conditional (`if let`). When it leaves, layout animation drops
  primary to the bottom edge; when it appears, it pushes primary up.
- Horizontal padding on the **inset content itself**. Parent
  `.padding(.horizontal)` on the body does **not** reach `safeAreaInset`
  chrome (Connections footers went edge-to-edge until the inset was padded).
- Scope path / page `.animation(..., value: path)` to the **body** only —
  apply it *before* `safeAreaInset`, never after. Animating the whole page
  (including the inset) makes the CTA cross-fade with the step instead of
  morphing.
- Multi-child `@ViewBuilder` content for a step must sit in a `VStack` (or
  other stack) **before** any `.frame(..., alignment:)`. Framing a bare
  tuple with `alignment: .topLeading` overlays every child at the same
  origin (Connections why screen “mixed up” layout).

### Portable kits (`Sources/Shared/`)
- App-agnostic UI that will leave Even (today: `ToastUI`) lives under
  `Shared/`, owns its resources (e.g. `.metal`), and takes style/motion via
  configuration + environment — **no** `EvenTokens` / `EvenMotion`.
- Even skin is a thin Design bridge (`ToastConfiguration+Even`,
  `.evenToastHost()`). Product copy (“Couldn’t reach Google”) stays in the
  Feature that talks to that service, not in the kit.
- Features present through `ToastClient` → `ToastHostCenter`; the Feature
  root attaches `.evenToastHost()` (local overlay, not a global `UIWindow`).

### Drawn success marks
- Prefer a `Shape` + `.trim` stroke over an SF Symbol pop-in. Delay, draw the
  tick, **then** reveal the pine disc (`ConnectionsDrawnCheckmark`) — fill
  after the stroke finishes, not before.

### App route after setup
- `AppReducer` path: boot → login → onboarding → **householdSetup** →
  **connections** → ready (Today + Inbox). Next design slice after Household
  is `ConnectionsFeature` / `Email & Calendar Setup.dc.html`.

### Programmatic pagers & art
- Fixed chrome (footer / CTA) via `safeAreaInset` (rules above); page content
  in a programmatic `ScrollView` (`scrollPosition`, often
  `.scrollDisabled(true)`).
- **`LazyHStack` does not save you** in a short pager — all pages still mount.
  Gate heavy illustrations to the **active page**, but **reserve height**
  (`Color.clear.frame(height:)` + `.overlay`) so title/subtitle don’t jump.
- Appear sequences (beam drop, drafts stamp, Sunday pour) remount via active
  gating + `onAppear` / cancel on `onDisappear`.
- Storytelling copy: centered, multiline. Forms stay leading.

### Beam / shared physics
- Domain-agnostic in `Design` (`EvenBeamScale` + configuration). Features map
  Summary → config (`EvenBeamScale+Summary`).
- Heavier left pan must **sink** (SpriteKit positive zRotation). Weight updates
  as pebbles **enter**, not after a settle timer. Parent balls to pans; seal
  colliders so nothing falls out. Share % that rides the tilt lives on the
  beam node, not floating SwiftUI overlays.

### Hygiene
- Every Feature surface gets an in-file `#Preview`. Single-screen Features:
  previews on the main `*View`. Multi-step: shell keeps a whole-flow preview;
  **each** `Views/` step previews that step. One preview per surface unless a
  variant earns its keep; fixtures from `*PreviewSupport` /
  `DesignPreviewSupport` only.
- A11y strings track real fixture values. Durable controls get
  `accessibilityIdentifier`s for UITests.
- Ignore `**/xcuserdata/`. Verify with Xcode MCP / `xcodebuild`, not claims.
