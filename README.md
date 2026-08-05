# Even

Household app for a couple — shared chores, Approval Inbox (email → tasks),
weighted Today beam, two-way Google Calendar. Domain: **thisiseven.app**.

## Open the app

```bash
open Even.xcworkspace
```

The workspace contains only `ios/Even.xcodeproj`. Package brain is **EvenKit**
(`Package.swift` at repo root). Do not also add the package root as a second
workspace item.

```bash
cd ios && xcodegen generate
# then build scheme Even for an iPhone simulator (iOS 18+)
```

## Layout

| Path | Role |
|---|---|
| `Sources/Core/` | Models, clients, Live, DI (`EvenCore`, `*Client`, …) |
| `Sources/Feature/` | TCA Features + `EvenApp` composition root |
| `Sources/Design/` | Tokens + shared UI primitives |
| `ios/` | Apple shell (iPhone, widgets, Watch) |
| `backend/` | `evend` Go API |
| `docs/` | Product docs, design-system HTML, web, stubs — see `docs/README.md` |
| `Tests/` | SPM test targets |

No shipping macOS app.

## Backend

```bash
cd backend && docker compose up -d --build
# API http://127.0.0.1:8091 — secrets from backend/.env
```

Contract: `docs/product/API.md`.

## Design contract

Preview Claude Design flows over HTTP (not `file://`):

```bash
cd docs/even-design-system && python3 -m http.server 8765
```

## Deploy coming-soon

```bash
cd docs/web/coming-soon && CLOUDFLARE_ACCOUNT_ID=64d6def322d7854f96a2460c2b1a88a4 \
  CLOUDFLARE_API_TOKEN=$CLOUDFLARE_PAGES_TOKEN \
  npx wrangler@4 pages deploy . --project-name=thisiseven --branch=main --commit-dirty=true
```

Agent guide: [`CLAUDE.md`](./CLAUDE.md). Architecture: [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).
