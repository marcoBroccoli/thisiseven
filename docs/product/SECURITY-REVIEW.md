# Even backend — threat model & hardening plan (EV-80)

Status: draft, 2026-08-02. Covers the `evend` API + self-hosted GoTrue +
Postgres stack in `backend/`. Written from static review of the code and
compose config (no runtime pen-test). Supersedes EV-80's original framing —
see **Correction** below.

## Correction: the API is not public yet

EV-80's ticket text says "now that the API is public (api.thisiseven.app)."
That's not accurate against the current repo: `docs/product/PRD.md` still
lists "Public exposure (api.thisiseven.app via Cloudflare tunnel)" as
**post-MVP, needs Umur's approval**, and there's no cloudflared config or
tunnel reference anywhere in `backend/` or `scripts/`. Today the API is
reachable only via `even-api.home` on the home LAN (Caddy route) and
`127.0.0.1:8091` locally.

That's good news for sequencing: this review can gate the public launch
instead of chasing an already-exposed surface. Recommend fixing EV-80's
wording and the matching parking-lot line in `BACKLOG.md` once this plan is
agreed, so the two stop contradicting each other.

## What's already solid

Worth naming, since the ticket reads like nothing's been done — a fair
amount of hardening already exists:

- **Household-scoping**: every data query I checked (tasks, drafts, money,
  calendar, reset/trades — 103 occurrences of `household_id` across 13
  files in `internal/api/`) filters by `m.HouseholdID`, resolved
  server-side from the authenticated user via `RequireMember`
  (`store.go:82`), never from a client-supplied id. No IDOR pattern found.
- **Rate limiting exists**: `httpx.PerUserLimit` (`httpx.go:50`) is wired
  onto both `/v1` route groups in `router.go` — 5 req/s for onboarding
  routes, 10 req/s for data routes, keyed by authenticated user id.
- **Request size limits**: `httpx.MaxBytes` caps bodies at 64KB
  (onboarding) / 256KB (data routes).
- **Container hardening**: `evend` runs `read_only: true`, on
  `distroless/static-debian12:nonroot` — no shell, no package manager, no
  root, in `Dockerfile` and `docker-compose.yml`.
- **Secrets**: `.env` is gitignored (`backend/.gitignore`); the compose file
  only references `${VAR}` names, matching the CLAUDE.md convention of
  secrets-by-name-only, sourced from `~/.env`.
- **Logging**: `httpx.Log` explicitly logs method/path/status/latency only
  — no bodies, no headers, no tokens (`httpx.go:104`).
- **DB/Postgres port** (`5433`) and the `evend` API port (`8091`) are both
  bound to `127.0.0.1` only in compose — nothing here is directly
  internet-facing without Caddy/a tunnel in front.

## Findings, prioritized

### High

**1. Open signup + autoconfirmed email is a *production* setting, not a debug-only one.**
`docker-compose.yml` sets `GOTRUE_DISABLE_SIGNUP: "false"` and
`GOTRUE_MAILER_AUTOCONFIRM: "true"` — this is the one compose file used for
the real deployed stack, not a separate debug profile. The iOS app's
`DebugAuthSheet` email/password form is `#if DEBUG`-gated client-side, but
that gate protects nothing: GoTrue itself will accept a signup + immediately
issue a valid session to *any* caller hitting `/auth/signup` directly,
without proving email ownership. Once the API is reachable beyond the LAN,
this is an open door to creating throwaway accounts (see finding 2).
Recommend: disable signup entirely in the prod compose (household creation
happens out-of-band, or via a one-time admin action) or require real email
confirmation (needs SMTP config) before flipping the tunnel on.

**2. No throttling on invite-code guessing beyond the generic per-user limiter.**
`POST /v1/households/join` sits behind `RequireAuth` + `PerUserLimit` only.
Because signup is open and autoconfirmed (finding 1), an attacker can mint
unlimited accounts, each getting its own 5 req/s bucket — there's no
IP-level or global cap. Codes are 6 chars from a 33-char alphabet (no
O/0/I/1), so the full keyspace is large, but the real risk is *any* open
(single-member) household is a viable target, not one specific code — with
few households today that's low-probability, but the exposure grows with
usage. Recommend a combined IP+account limiter specifically on the join
endpoint, and/or a per-code failed-attempt lockout. Note this interacts with
the household-setup UX just shipped (EV-47), which promises "one code, works
exactly once, never expires" — any fix here (expiry, lockout) needs a
product call, not just a backend patch.

### Medium

**3. `/auth/*` has no rate limiting at the evend layer at all.**
The reverse proxy in `router.go:44` forwards to GoTrue with no
`PerUserLimit` (it can't — there's no authenticated user yet at that point)
and no IP-based limiter either. GoTrue has its own internal defaults, but
none of the `GOTRUE_RATE_LIMIT_*` env vars are set explicitly in
`docker-compose.yml`, so the stack is relying on whatever supabase/auth
v2.193.0 ships with, unverified. Recommend: set `GOTRUE_RATE_LIMIT_*`
explicitly (don't inherit defaults silently) and/or add an IP-keyed
limiter in front of `/auth/*` in the chi router.

**4. Refresh token rotation isn't explicitly configured.**
`GOTRUE_JWT_EXP=3600` (1hr access token) is reasonable and deliberate. But
no `GOTRUE_SECURITY_REFRESH_TOKEN_REUSE_INTERVAL` (or equivalent) is set, so
refresh-token rotation/reuse-detection is whatever v2.193.0 defaults to.
Recommend confirming (via GoTrue's docs for this version, or a runtime
check) that rotation-on-use is active, and setting the reuse interval
explicitly rather than trusting the default.

**5. HS256 shared secret is a single point of compromise.**
`internal/auth/verify.go` correctly pins `jwt.WithValidMethods([]string{"HS256"})`
and rejects alg confusion — that part's fine. The structural risk is that
the same secret both signs (GoTrue) and verifies (evend); if it ever leaks
from either side, an attacker can forge tokens for any user. Recent GoTrue
versions support asymmetric signing (RS256/ES256 + JWKS), where evend would
only ever hold a public key. Worth a scoped research spike — this is a
bigger lift (GoTrue config + evend verifier rewrite + secret rotation plan)
so shouldn't block the current MVP, but should happen before the stack
handles more than two people's data.

**6. No dependency/base-image update mechanism.**
No Dependabot/Renovate config anywhere in the repo (checked `.github/` — the
only workflow is `deploy-web.yml` for the coming-soon page). `go.mod`,
`supabase/auth:v2.193.0`, and `postgres:17-alpine` are all hand-pinned with
no automated staleness/CVE signal. Recommend adding Dependabot for the Go
module graph and Docker base images at minimum — low effort, closes a real
gap (GoTrue and Postgres both take security patches regularly).

### Low / confirm-only

**7. Debug HTTP paths are a client-side illusion, not a real boundary.**
Same root cause as finding 1: anything gated by `#if DEBUG` in the iOS app
provides no protection against someone calling the API directly with curl.
Not a new fix — folded into finding 1 — but worth remembering when reasoning
about "debug-only" surface area anywhere else in the app.

**8. Tunnel exposure, when it happens.**
Not yet built (see Correction). When it is: recommend standing it up only
after findings 1–3 land, restricting the tunnel to `/healthz`, `/auth/*`,
and `/v1/*` explicitly (nothing else needs to be reachable), and keeping the
existing `read_only`/nonroot container posture unchanged end to end.

## What I couldn't verify statically

- GoTrue v2.193.0's actual default rate limits and refresh-rotation
  behavior — needs a runtime check against the compose stack (a quick curl
  loop), not guessing from docs that may not match this pinned version.
- Whether Caddy (`even-api.home` route, referenced in CLAUDE.md but its
  config lives outside this repo on the home server) adds any of its own
  rate limiting or IP filtering in front of evend today.

## Suggested sequencing

1. Fix findings 1 and 2 together (signup policy + join-endpoint throttling)
   — they compound each other and are the only items that actually gate
   "safe to expose publicly."
2. Set explicit `GOTRUE_RATE_LIMIT_*` / refresh-rotation env vars (3, 4) —
   config-only, no code change, cheap to do alongside 1–2.
3. Add Dependabot (6) — one-time setup, no ongoing cost.
4. Research spike on asymmetric JWT signing (5) — scope it, don't block on
   it.
5. Stand up the Cloudflare tunnel (8) only after 1–3 are done.
6. Correct EV-80's wording and the stale parking-lot line in `BACKLOG.md`.

None of the above has been implemented yet — this is the plan EV-80 asked
for. Say which items to act on and I'll make the corresponding config/code
changes (most of 1–3 are docker-compose.yml / router.go edits).
