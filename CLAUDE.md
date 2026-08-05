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
