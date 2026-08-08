# evend — Even's backend

One compose stack: **Postgres 17** (auth + app data), **GoTrue** (Supabase
Auth, self-hosted — Apple sign-in + debug email accounts), **evend** (Go API,
chi + pgx). The app talks to ONE origin: evend proxies `/auth/*` to GoTrue and
serves `/v1/*` itself. Contract: `../docs/product/API.md`.

## Run

```bash
cp .env.example .env       # secrets from ~/.env (THISISEVEN_*)
docker compose up -d --build
curl -s localhost:8091/healthz   # {"ok":true}
./scripts/smoke.sh               # full happy path through the real stack
```

Listens on `127.0.0.1:8091` (Caddy/`even-api.home` fronts it for LAN),
Postgres test port `127.0.0.1:5433`.

Household realtime uses `GET /v1/ws/household` (WebSocket). Caddy’s
`reverse_proxy` upgrades WebSockets by default — no extra config for
`even-api.home`. `evend` sets `WriteTimeout: 0` so long-lived sockets are
not killed by the HTTP write deadline.

## Layout

- `cmd/evend/` — main + embedded migrations (schema_migrations, run at boot)
- `internal/config` — env config (`EVEN_DATABASE_URL`, `EVEN_GOTRUE_JWT_SECRET`,
  `EVEN_GOTRUE_URL`, `EVEN_ADDR`)
- `internal/auth` — GoTrue HS256 access-token verification (evend never mints)
- `internal/httpx` — middleware (auth gate, rate limit, log, recover) + the
  `{"error":{code,message}}` envelope
- `internal/api` — handlers; `store.go` resolves caller → member/household/
  open week once per request (`RequireMember`)
- `db-init/` — first-boot SQL: `auth` schema + the Supabase roles GoTrue's
  bundled migrations grant to (postgres, supabase_auth_admin, anon,
  authenticated, service_role — all nologin)

## Semantics worth knowing

- All money is integer euro cents; balances round the odd cent up.
- One open week per household (partial unique index); `POST /v1/week/close`
  applies accepted trades, archives finished one-offs, opens the next week.
  Optional `{week_id}` body guards double-taps (409 `week_already_closed`).
- Toggling a task credits the pebble to the task's **owner**, whoever taps.
- Trades: the non-proposer accepts (409 `own_trade` otherwise).
- "today" and due phrases are computed in Europe/Amsterdam (tzdata embedded).
- The shared Google calendar is a **mirror**: Even publishes, the partner gets
  a `reader` grant (never writer). Google gives a secondary calendar one owner,
  stored as `households.calendar_owner_member_id` (migration 013) — that
  member's token performs every calendar write. `POST /v1/google/calendar/add`
  is the partner's one-tap confirm (ACL reader + CalendarList insert), and
  `POST /v1/google/disconnect` hands ownership over **before** deleting the
  leaving owner's token: ACL `owner` → ACL `writer` → recreate-and-migrate,
  whichever Google accepts first.

### Google OAuth scope — re-consent required (2026-08)

The Calendar scope moved from `calendar.events` to the full
`https://www.googleapis.com/auth/calendar` (`gmail.readonly` unchanged) in
`internal/google/google.go` `AuthURL`, `scripts/google-authorize.sh` and the
iOS client (`Sources/Core/EvenCore/GoogleConnect.swift`). Creating a secondary
calendar, granting ACL and inserting into a CalendarList are not covered by
`calendar.events`. **Connections made before the bump keep working for Gmail
but fail the sharing calls**: Google answers 403 `insufficientPermissions`,
which surfaces as `reconnect_required` / `owner_reconnect_required` (add) or a
`retry_required` todo carrying "reconnect Google" (publish). Never a silent
success — the user has to run the connect flow again.

## Tests

```bash
# unit (JWT verifier):
docker run --rm -v "$PWD":/src -w /src golang:1.24-alpine go test ./internal/auth
# hub / api unit tests (no stack):
docker run --rm -v "$PWD":/src -w /src golang:1.24-alpine go test ./internal/api -count=1
# integration (full flow; needs the stack up):
source .env && docker run --rm -v "$PWD":/src -w /src --network evend_default \
  -e EVEN_TESTDB="postgres://even:${EVEN_DB_PASSWORD}@db:5432/even?sslmode=disable" \
  -e EVEN_GOTRUE_JWT_SECRET="$GOTRUE_JWT_SECRET" \
  golang:1.24-alpine go test ./...
```

### Manual: household realtime (two clients)

With `docker compose up` and two sims (or sim + device) signed into the same
household, both foregrounded on Today:

1. Toggle a chore on A — check + beam update immediately on A.
2. B should refetch summary over `GET /v1/ws/household` → invalidate →
   `GET /v1/summary` and update list + beam without pull-to-refresh.
3. Kill the API briefly — A still toggles locally; on failure toast + reload.
   When the API returns, sockets reconnect with backoff.

## Apple sign-in

GoTrue is configured for the native id_token grant:
`POST /auth/token?grant_type=id_token` with
`{"provider":"apple","id_token":…,"nonce":<raw nonce>}` — audience must be
`com.umuryavuz.even` (`GOTRUE_EXTERNAL_APPLE_CLIENT_ID`). No Apple secret
needed for the native flow. Debug builds use email+password
(`/auth/signup`, autoconfirmed — no SMTP configured).
