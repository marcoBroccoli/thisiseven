# Even MVP — Backlog (micro tickets)

Status: `[ ]` open · `[x]` done · `[~]` in progress. Order within a phase is
execution order. AC = acceptance criteria.

## P0 Foundations
- [x] **EV-01** Product docs — PRD, battle plan, backlog in `docs/product/`.
- [x] **EV-02** ~~Cloud project~~ → BLOCKED by free-tier limit (2 active
  projects: Vet App, Toolkit). Pivot: self-hosted GoTrue in the evend
  compose. `scripts/provision-supabase.sh` kept for a later cloud move.
- [x] **EV-03** GoTrue (supabase/auth image) in compose: auth schema in the
  shared Postgres, Apple provider (`com.umuryavuz.even`), autoconfirmed
  email for debug accounts, JWT secret in env. AC: signup + password grant +
  refresh work via curl through evend's `/auth/*` proxy.

## P1 Backend (evend)
- [x] **EV-10** `backend/` scaffold: go.mod, chi router, config from env,
  `/healthz`, `/auth/*` reverse proxy → GoTrue. Dockerfile (multi-stage,
  distroless), docker-compose (evend 127.0.0.1:8091 + gotrue + postgres17
  named volume). AC: `docker compose up` → healthz 200, auth proxy works.
- [x] **EV-11** Migrations (embedded, run at boot): households, members,
  weeks, tasks, completions, drafts, expenses, settlements, appreciations,
  trades. AC: fresh boot creates schema; second boot is a no-op.
- [x] **EV-12** Auth middleware: verify GoTrue JWT (HS256, shared secret),
  extract user id; 401 on bad/expired. AC: unit test with forged/valid tokens.
- [x] **EV-13** Households: `POST /v1/households` (create, invite code),
  `POST /v1/households/join`, `GET /v1/me` (member, partner, household,
  open week). AC: 2nd join sets teal; 3rd member rejected 409.
- [x] **EV-14** Tasks: CRUD + `POST /v1/tasks/{id}/toggle` (creates/deletes
  completion in open week). AC: toggle idempotent per week; weight snapshot.
- [x] **EV-15** Summary: `GET /v1/summary` → per-member pebbles (weights) of
  open week, percentages, section'd open tasks, pending-draft count. AC:
  matches design math (A% rounding, beam input).
- [x] **EV-16** Drafts: propose, list pending, `PATCH` (title/owner/amount/
  due/reminder), approve (→ admin task, tx), dismiss. AC: approve is
  transactional; resulting task carries due + owner + weight 2 default.
- [x] **EV-17** Money: expenses CRUD-lite (add, list), `GET /v1/balance`,
  `POST /v1/settle` (marks all unsettled, records settlement, tx). AC:
  balance = (payerA−payerB)/2 signed; settle → 0; settlement in list feed.
- [x] **EV-18** Reset: appreciations get/put (per week, per direction),
  trades propose/accept/list, `GET /v1/reset-summary` (split bars + biggest
  carry sentence), `POST /v1/week/close` (tx: apply accepted trades, close
  week, open next, reset recurring tasks, archive one-offs done). AC: close
  is atomic + idempotent-guarded; new week empty pans.
- [x] **EV-19** `go test` integration suite against compose db covering
  EV-13..18 happy paths + auth failures. AC: green in CI-style run.
- [x] **EV-20** Deploy: compose up on the mini, Caddy route `even-api.home`
  via `~/scripts/add-home-service.sh even-api 8091`. AC: `dig even-api.home`
  → both IPs; healthz via even-api.home.

## P2 App plumbing
- [x] **EV-30** `EvenCore` target (+ tests target entry in Package.swift):
  API models (Codable, snake_case), `EvenAPIClient` (async URLSession, auth
  header injection, error enum), `APIEnvironment` (localhost / even-api.home).
- [x] **EV-31** `SupabaseAuthService`: Apple id_token grant, email+password
  (debug), refresh, Keychain persistence (`com.umuryavuz.even.session`).
  AC: unit-testable request factories; tokens survive relaunch.
- [x] **EV-32** `SessionStore` (@Observable): signed-out / needs-household /
  ready states; bootstrap from Keychain + `GET /v1/me`.
- [x] **EV-33** SIWA capability: entitlements file + project.yml update;
  register bundle id + SIWA via ASC API when shipping (deferred note).

## P3 App UI (EvenMobile)
- [x] **EV-40** Design system: `EvenTheme` (light/dark token sets, member
  color resolution), bundled Newsreader + SourceSans3 fonts, grain overlay,
  stamp/toast view, pill + chip + check components. Demo seed deleted.
- [x] **EV-41** Custom tab bar (4 items, SVG-derived icons, badge count) +
  root scaffold + wordmark header + dark toggle (persisted).
- [x] **EV-42** Onboarding: welcome, SIWA button (+debug email form), create
  vs join household, name entry, invite-code share/entry, waiting/solo state.
- [~] **EV-43** Today: beam scale view (rotation math, pans, pebble layout,
  pct, captions) + section lists + task row (check animation, heft, owner
  chip) + Quick Add sheet. Wired to summary/tasks API.
- [~] **EV-44** Inbox: card list, propose sheet, review bottom sheet
  (title field, owner pills, reminder chips, dismiss/approve), stamp toasts,
  empty state, badge. Wired.
- [~] **EV-45** Money: balance card + avatars + coin, settle interaction,
  expense list + add sheet. Wired.
- [~] **EV-46** Reset: intro, progress header, step 1 bars + biggest carry,
  step 2 appreciation cards, step 3 trades, close-week action, poured-out
  end screen. Wired.

## P4 Polish
- [ ] **EV-50** Motion pass: pebbleDrop, beam spring, coinSlide, stampIn,
  sheet transitions, fadeUp.
- [ ] **EV-51** Dark mode pass across all screens (design's dark palette).
- [ ] **EV-52** Empty/error states: fresh household, offline banner, retry.
- [ ] **EV-53** Refresh strategy: pull-to-refresh + foreground refetch.

## P5 Verification
- [~] **EV-60** `swift test` + `go test` green; macOS app still builds.
- [~] **EV-61** Simulator E2E with two debug accounts per PRD definition of
  done (pair → tasks → beam → draft approve → money settle → reset close).
- [ ] **EV-62** SIWA smoke on simulator (button, flow start) + written
  device-test plan.
- [ ] **EV-63** Screenshots (4 tabs × light/dark) → `docs/screenshots/`,
  README + CLAUDE.md updated, final commit.

## P6 Google integration (promoted to MVP core by Umur, 2026-07-17)
- [x] **EV-70** evend google module: OAuth token store (google_accounts),
  connect/status/disconnect endpoints, google-authorize.sh loopback flow.
- [x] **EV-71** Gmail discovery sync: HouseholdTodo label or discovery
  query, heuristic extraction (title/amount/due/urgency, 0.60 confidence
  gate), dedupe by gmail_message_id, 30-min background ticker + manual
  /v1/google/sync.
- [x] **EV-72** Approve → Google Calendar all-day event with the draft's
  reminder offset; event id/url on the task; calendar failure never aborts
  the approve.
- [x] **EV-73** One-time consent for the household account via browser
  automation; refresh token stored server-side.
- [x] **EV-74** App: Inbox shows GMAIL DISCOVERY header + sync affordance +
  connected status; approved tasks link out to the calendar event.
- [x] **EV-75** E2E: send a bill-like email to the household account,
  sync, see the draft, approve, verify the event lands in Google Calendar.

## Post-MVP parking lot
Push notifications · public API via Cloudflare tunnel (api.thisiseven.app) ·
TestFlight (needs explicit approval) · Android · uneven splits · week
history browser · calendar retry/external-change reconciliation (mac
prototype has it; port later).
