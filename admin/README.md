# Even Admin — the operations console

A standalone Go service plus an embedded React SPA. It reads **evend's own
Postgres** directly and owns nothing in it except the `admin` schema.

It is a separate binary and a separate compose project on purpose: the console
must be deployable, restartable and killable without touching the API a
household actually depends on. Nothing in `backend/` knows this service exists.

```
admin/
  Dockerfile              # 3 stages: vite build → go build (SPA embedded) → distroless
  docker-compose.yml      # project `even-admin`, joins the external `evend_default` network
  .env.example            # every variable, by name only — no secrets in this repo
  README.md
  server/                 # module github.com/marcoBroccoli/thisiseven/admin
    cmd/adminsrv/main.go
    internal/config/      # env → Config, no insecure defaults
    internal/adminauth/   # bcrypt, RFC 6238 TOTP, session tokens
    internal/store/       # pool, admin-schema migrations, first-admin bootstrap
      migrations/001_admin_schema.sql
      migrations/002_seed_settings.sql
    internal/api/         # handlers + router (read this file as the contract)
    internal/web/         # go:embed of the built SPA
      dist/               # committed build output — go:embed needs it to exist
  web/                    # React 18 + Vite + TypeScript
    src/{api.ts,App.tsx,components/,pages/,lib/}
    e2e/smoke.spec.ts     # Playwright; not part of the build gate
```

## What runs where

| Piece | Where it runs | Port |
|---|---|---|
| `adminsrv` Go binary | `even-admin` compose project, on the `evend_default` network | listens `:3025` in-container |
| Published to host | `127.0.0.1:${ADMIN_HOST_PORT}` | **3026** by default — see the port note |
| Postgres | evend's existing `db` service | `db:5432` in-network, `127.0.0.1:5433` from the host |
| evend (health probe target) | evend's existing `evend` service | `http://evend:8080/healthz` |

> ⚠️ **Port note.** The brief asked for `:3025`, and the container does listen
> there. On this machine host port 3025 is already taken by the `glance`
> container, so `ADMIN_HOST_PORT` defaults to **3026**. Set it back to 3025 in
> `admin/.env` once glance moves.

## Security posture

- **Email + password + mandatory TOTP.** The password step *never* issues a
  session — only a verified 6-digit code does. On first sign-in the server mints
  a candidate secret, returns an `otpauth://` URI (the QR is drawn in-browser by
  the bundled `qrcode` package, nothing is fetched), and writes the secret to the
  account **only after** a code proves the phone has it.
- **Server-side sessions.** The cookie carries a random 256-bit token; the row
  stores its SHA-256. HttpOnly, SameSite=Lax, Secure (unless
  `ADMIN_COOKIE_SECURE=false`), 12 h by default. Sign-out revokes the row.
  Changing your password revokes every *other* session.
- **Rate limiting.** 8 failed attempts per email or 20 per IP in 15 minutes →
  429. A login challenge dies after 5 wrong codes and 5 minutes.
- **Roles.** `admin` can write; `viewer` gets 403 on every mutating endpoint.
- **Audit.** Every write records `admin.audit_log` with actor, action, target,
  IP and whole-row before/after JSON.
- **CSP `'self'`** with no CDN anywhere — the bundle is inside the binary, so the
  policy is absolute rather than a list of allowances. Plus `nosniff`,
  `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`.

## The `admin` schema

Applied by **this** service at boot, tracked in `admin.schema_migrations` —
deliberately **not** part of evend's migration chain, so the two deploy and roll
back independently.

`admin_users · sessions · login_challenges · login_attempts · audit_log ·
settings · notification_outbox`

There are **no foreign keys into the product tables**: an audit row or a queued
push must outlive the household it names, and evend must stay free to drop and
recreate anything it owns.

### Two things the UI states plainly, because they are true

- **`admin.settings` is a staging area. evend does not read it.** Editing a key
  records intent and an audit row; wiring a key into the service is a deliberate
  backend change, one key at a time.
- **`admin.notification_outbox` queues, it does not deliver.** There is no APNs
  sender yet (that is roadmap task #15). Rows sit at `status='queued'`. The
  compose UI, audience validation, recipient estimate, outbox history and cancel
  are all real; delivery is not.

## Features

1. **Dashboard** — 8 live totals + a 14-day trend (new users, households, tasks,
   drafts, completions) + a "needs attention" list (calendar retries, todos
   deleted in Google, mailboxes stale >24 h, households with no active member,
   failed admin logins).
2. **Users** — `auth.users` joined to memberships. Search by email, id or display
   name. Detail page: identity, every household incl. departed seats, per-household
   Google/draft/task/completion counts, invites addressed to them, merged activity feed.
3. **Households** — list + detail with tabs (members, tasks, weeks, money,
   activity), calendar owner/id/sync breakdown, invite state. **Writes:** revoke a
   pending invite, regenerate the invite code — both audited.
4. **Gmail & Calendar ops** — per-mailbox scan stats and staleness, the
   mail→verdict→draft→todo funnel, and every task in `retry_required` /
   `external_deleted` / `external_changed` with its error.
5. **Settings** — `admin.settings` JSON key/value editor.
6. **Notifications** — compose to all / one household / one user, schedule,
   recipient estimate, outbox history, cancel while queued.
7. **Audit log** — filterable, with a before/after diff view.
8. **Health** — evend `/healthz` probe, pool stats, database size, exact row
   counts for 20 tables, applied migrations, 24 h login tallies.

Keyboard: `⌘K` / `/` opens the palette (pages + live household/user search),
`g` then `d u h o n s a e` jumps.

## Local development

Node and npm on the host are enough for the frontend:

```bash
cd admin/web
npm install
npm run build      # tsc --noEmit && vite build → ../server/internal/web/dist
npm run dev        # :5273, proxies /api → 127.0.0.1:3025
```

The Go service needs a toolchain (there is none on the host today — use Docker,
one container at a time):

```bash
docker run --rm -v "$PWD/admin/server":/src -w /src golang:1.24-alpine \
  sh -c 'go vet ./... && go test ./...'
```

### Tests

- **`internal/adminauth`** — pure unit tests, no database. RFC 6238 vectors,
  drift window, bcrypt salting/verification, strength floor, token entropy and
  hash stability.
- **`internal/api`** — handler tests against a real Postgres. They **skip**
  unless `ADMIN_TESTDB` is set, and **refuse any DSN whose database is not
  literally named `even_test`** — the same guard evend's suite uses, for the same
  reason (fixtures leaked into production once already).

```bash
docker exec evend-db-1 psql -U even -d even -c 'create database even_test'
docker exec evend-db-1 sh -c 'pg_dump -U even --schema-only even | psql -U even -d even_test'

docker run --rm --network host -v "$PWD/admin/server":/src -w /src golang:1.24-alpine \
  sh -c 'ADMIN_TESTDB="postgres://even:PW@127.0.0.1:5433/even_test?sslmode=disable" go vet ./... && \
         ADMIN_TESTDB="postgres://even:PW@127.0.0.1:5433/even_test?sslmode=disable" go test ./...'
```

Tests that need evend's product tables skip themselves if `even_test` only has
the admin schema, so a bare test database still exercises auth, settings,
notifications and the audit log.

- **Playwright** (`web/e2e/smoke.spec.ts`) is *not* in the build gate and
  downloads no browser on install. It checks that the embedded bundle is served,
  the SPA falls back on a deep link, the API refuses unauthenticated reads, and
  the security headers are set:

```bash
cd admin/web
npx playwright install chromium
ADMIN_BASE_URL=http://127.0.0.1:3026 npm run test:e2e
```

## Deploy

```bash
cd admin
cp .env.example .env
# fill EVEN_DB_PASSWORD (same value as backend/.env), and for the FIRST boot only:
#   ADMIN_BOOTSTRAP_EMAIL / ADMIN_BOOTSTRAP_PASSWORD  (≥12 chars, letters + digit/symbol)
docker compose up -d --build
docker compose logs -f admin        # expect "even admin listening"
```

Sign in once at the URL below, scan the QR, then **delete the two bootstrap
lines from `.env`**. `Bootstrap` refuses to run once any admin exists, but there
is no reason to leave a password on disk.

### Expose it — `even-admin.home` (LAN + tailnet)

```bash
~/scripts/add-home-service.sh even-admin 3026
dig @192.168.1.135 even-admin.home +short     # MUST print BOTH 192.168.1.135 and 100.95.230.127
```

The helper is idempotent and does the two AdGuard rewrites, the Caddy block and
the validate/reload. Two rewrites or it is dead on the tailnet.

For a plain-http `.home` test, set `ADMIN_COOKIE_SECURE=false` in `admin/.env`
and recreate the container — otherwise the browser drops the session cookie and
sign-in appears to succeed and then immediately fail.

### Expose it — `admin.thisiseven.app` (public)

1. Cloudflare DNS: add `admin` as a **proxied** CNAME to the existing tunnel
   hostname for the `thisiseven.app` zone.
2. Cloudflare Zero Trust → Networks → Tunnels → the existing tunnel → **Public
   hostname**: `admin.thisiseven.app` → `http://127.0.0.1:3026`.
3. Strongly recommended: put a **Cloudflare Access** policy in front of that
   hostname (one-time PIN to your address). The console's own password+TOTP is
   the real gate, but Access keeps the login page itself off the open internet.
4. Keep `ADMIN_COOKIE_SECURE=true` — Cloudflare terminates TLS, so the cookie
   must stay `Secure`.
5. `X-Forwarded-For` from the tunnel is what the rate limiter and audit log
   record as the client IP; that is intentional and already handled.

Optionally add an Uptime Kuma monitor on `http://127.0.0.1:3026/healthz`
(expects `{"ok":true}`, no auth).

### Rollback

```bash
cd admin && docker compose down          # evend is untouched
```

The `admin` schema stays behind. It holds no product data — dropping it costs
you the audit history and the admin accounts, nothing else.
