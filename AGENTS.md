# AGENTS.md

Project guide for AI coding agents (Claude Code, Cursor, etc.).

**The full guide — project structure, what each part does, data model, build/test
commands, and conventions — lives in [`CLAUDE.md`](./CLAUDE.md).** Read it first.

Quick orientation:
- `backend/` — the `evend` Go API (all app data; auto-runs SQL migrations on start).
- `Sources/EvenCore` + `Sources/EvenMobile` — the iOS app (SwiftUI) and its API client.
- `ios/` — the iOS Xcode project (generated via `xcodegen` from `project.yml`).
- `docs/product/API.md` — the **API contract, source of truth**. Keep it and
  `backend/internal/api/router.go` in sync.
- Secrets are referenced by NAME only (`~/.env` on the home server); never commit them.
