# Even MVP — Battle Plan

Goal: from today's "shell v1 on demo data" to a fully working, real-data MVP
per `PRD.md`. Backlog with micro tickets: `BACKLOG.md`.

## Phases

**P0 — Foundations (sequential, fast)**
Docs (this file, PRD, backlog) · auth provider decision. Outcome: cloud
Supabase blocked by free-tier limit → **self-hosted GoTrue** in the evend
compose (Apple provider for `com.umuryavuz.even`); secrets in `~/.env`.

**P1 — Backend `evend` (parallel with P2/P3 app work)**
`backend/` in this repo, copying kilod's proven shape (Go 1.24, chi, pgx,
distroless Docker, compose with Postgres 17, 127.0.0.1:8091). Supabase JWT
verification middleware. Full REST surface + week-close transaction.
Integration-tested with `go test` against the compose db. Caddy route
`even-api.home`.

**P2 — App plumbing**
New `EvenCore` target: models mirroring the API, `EvenAPIClient`
(URLSession, async), Supabase auth service (Apple id_token grant + refresh +
Keychain, kilo's `Services.swift` as reference), session store, environment
switch (localhost / even-api.home).

**P3 — App UI**
`EvenMobile` rebuilt to the design: token system + fonts, custom tab bar,
Today (scale + rows + quick add), Inbox (cards + review sheet + stamp),
Money, Reset flow, onboarding/pairing. Demo seed deleted.

**P4 — Integration polish**
Animations (beam spring, pebble drop, check draw, coin slide, stamp), dark
mode, empty states, error/offline toasts, pull-to-refresh + foreground
refresh (no realtime in MVP).

**P5 — Verification**
Two email-auth accounts in simulator → full E2E per PRD "definition of
done". SIWA verified to the extent the simulator allows (button + flow
start; full loop needs a device/TestFlight — NOT shipped without approval).
Screenshots to `docs/screenshots/`. `swift test` + `go test` green.

## Execution notes

- Backend and app UI are independent workstreams; UI develops against the
  compiled API contract (`docs/product/API.md`, written with the backend).
- Existing macOS `HouseholdCommandCenter` + `HouseholdCore` stay untouched
  and must keep building (`swift test` gate). Even's mobile core is separate
  (`EvenCore`) — no entanglement with the Gmail/Calendar mac prototype.
- Commits per ticket-cluster, conventional style, no pushes unless asked.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| ~~Free-tier slot~~ — HIT (2 active projects, both prod) | Pivoted to self-hosted GoTrue in our compose; cloud script kept for later |
| SIWA flaky in simulator; sim holds Umur's live Apple session | Email+password debug auth path for E2E; never `simctl erase` without care (memory rule); SIWA fully verified later on device |
| GoTrue self-host config drift vs cloud API | Auth calls go through evend's `/auth/*` proxy with the standard GoTrue API shape — cloud move is a base-URL swap |
| ATS blocks http://even-api.home on device | Simulator uses localhost; ATS exception documented for device builds; proper TLS post-MVP via tunnel |
| Newsreader/Source Sans 3 font fetch fails | System serif/sans standins already in place; fonts are a swap-in ticket |
| 16GB RAM server | evend+pg ≈ <300MB; no Supabase self-host stack; gradle daemon stays off |
| Xcode 26 Swift 6 crash (per repo README) | Package stays swift-tools 5.10 language mode |

## Sequencing

P0 → (P1 ∥ P2) → P3 → P4 → P5. P3 can start on tokens/static layout before
P2 lands; data wiring waits for P1+P2.
