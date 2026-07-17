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

## Tests

```bash
# unit (JWT verifier):
docker run --rm -v "$PWD":/src -w /src golang:1.24-alpine go test ./internal/auth
# integration (full flow; needs the stack up):
source .env && docker run --rm -v "$PWD":/src -w /src --network evend_default \
  -e EVEN_TESTDB="postgres://even:${EVEN_DB_PASSWORD}@db:5432/even?sslmode=disable" \
  -e EVEN_GOTRUE_JWT_SECRET="$GOTRUE_JWT_SECRET" \
  golang:1.24-alpine go test ./...
```

## Apple sign-in

GoTrue is configured for the native id_token grant:
`POST /auth/token?grant_type=id_token` with
`{"provider":"apple","id_token":…,"nonce":<raw nonce>}` — audience must be
`com.umuryavuz.even` (`GOTRUE_EXTERNAL_APPLE_CLIENT_ID`). No Apple secret
needed for the native flow. Debug builds use email+password
(`/auth/signup`, autoconfirmed — no SMTP configured).
