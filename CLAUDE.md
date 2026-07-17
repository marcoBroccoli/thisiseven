# thisiseven — workspace guide

**Even** — "Money, settled weekly." / Household Command Center for a couple
(Umur + Beste). Domain: **thisiseven.app** (Cloudflare, zone in ~/.env context).

## Layout
- `Sources/HouseholdCore/` — domain models + workflow services (testable core)
- `Sources/HouseholdCommandCenter/` — SwiftUI macOS app target
- `Tests/HouseholdCoreTests/` — 12 test suites; run `swift test` before claiming done
- `supabase/` — starter schema + Edge Function stubs
- `docs/` — Google/Supabase test setup; `docs/design/` — design language + the
  Claude Design export (`even-play.dc.html`) and token table
- `web/coming-soon/` — the LIVE thisiseven.app page (static: index/robots/sitemap)
- `scripts/run-mac-app.sh` — launch the mac app

## Commands
- Test: `swift test`
- Run app: `./scripts/run-mac-app.sh`
- Deploy coming-soon page (Cloudflare Pages project `thisiseven`):
  ```bash
  cd web/coming-soon && CLOUDFLARE_ACCOUNT_ID=64d6def322d7854f96a2460c2b1a88a4 \
    CLOUDFLARE_API_TOKEN=$CLOUDFLARE_PAGES_TOKEN \
    npx wrangler@4 pages deploy . --project-name=thisiseven --branch=main --commit-dirty=true
  ```
  (token in ~/.env; domain + www are attached to the Pages project, GSC verified —
  do NOT delete the google-site-verification TXT record on the zone.)

## Conventions
- Local-first: JSON local store is authoritative; Gmail imports MERGE, never replace
  user-edited/approved items. Calendar approval goes through the mockable client.
- Design language lives in `docs/design/README.md` — cream paper / espresso ink /
  terracotta accent, Newsreader + Source Sans 3. Keep new UI on these tokens.
- Google OAuth is desktop/test-user flow; secrets never in the repo (~/.env on the
  home server; Keychain for tokens).
