# AGENTS.md

Project guide for AI coding agents (Claude Code, Cursor, etc.).

**The full guide — project structure, what each part does, data model, build/test
commands, and conventions — lives in [`CLAUDE.md`](./CLAUDE.md).** Read it first.

Quick orientation:
- `backend/` — the `evend` Go API (all app data; auto-runs SQL migrations on start).
- SPM package **`EvenKit`** (one package): targets under `Sources/Core/`,
  `Sources/Feature/`, `Sources/Design/` — folder layers, not separate packages.
- Open **`Even.xcworkspace`** (only `ios/Even.xcodeproj`). Platforms: iOS 18+ /
  watchOS 11+ — no macOS app. Build with `xcodebuild` / Xcode.
- `docs/even-design-system/` — MVP UI contract; Features map to those flows.
- Non-app resources live under `docs/` (see `docs/README.md`).
- `docs/ARCHITECTURE.md` + `docs/superpowers/specs/2026-08-05-evenkit-tca-design-system-adaptation.md`.
- `docs/product/API.md` — the **API contract, source of truth**. Keep it and
  `backend/internal/api/router.go` in sync.
- Secrets are referenced by NAME only (`~/.env` on the home server); never commit them.
