# Lightweight Local Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist household drafts locally so the app can be tested realistically before adding Supabase or another production database.

**Architecture:** Add a small JSON-backed store in `HouseholdCore` that saves `InboxDraft` records and per-draft reply text. Add a deterministic merge policy so Gmail discovery inserts new emails while preserving existing edited, approved, rejected, and retry drafts.

**Tech Stack:** Swift, Foundation `Codable`, `JSONEncoder`/`JSONDecoder`, Swift Package tests, SwiftUI app integration.

---

### Task 1: Core Local Store

**Files:**
- Create: `Sources/HouseholdCore/HouseholdLocalStore.swift`
- Test: `Tests/HouseholdCoreTests/HouseholdLocalStoreTests.swift`

- [ ] Write tests that save/load drafts and reply text through a temporary JSON file.
- [ ] Verify tests fail because `HouseholdLocalStore` does not exist.
- [ ] Implement `LocalHouseholdState`, `LocalReplyDraft`, and `HouseholdLocalStore`.
- [ ] Verify targeted tests pass.

### Task 2: Import Merge Policy

**Files:**
- Modify: `Sources/HouseholdCore/HouseholdLocalStore.swift`
- Test: `Tests/HouseholdCoreTests/HouseholdLocalStoreTests.swift`

- [ ] Write tests that imported drafts merge by `source.gmailMessageID`.
- [ ] Preserve existing edited/status fields when the same Gmail message is imported again.
- [ ] Append new Gmail messages and preserve manual entries.
- [ ] Verify targeted tests pass.

### Task 3: App Integration

**Files:**
- Modify: `Sources/HouseholdCommandCenter/DemoHouseholdStore.swift`

- [ ] Load persisted state on startup.
- [ ] Save after import, edit, approve, reject, manual create, and reply text changes.
- [ ] Merge Gmail discovery results into existing state instead of replacing the inbox.
- [ ] Keep demo seed only as first-launch fallback.

### Task 4: Verification

**Files:**
- Modify: `README.md`

- [ ] Document local storage behavior and reset path.
- [ ] Run `swift test`.
- [ ] Run `./scripts/run-mac-app.sh --build-only`.
- [ ] Relaunch with `./scripts/run-mac-app.sh`.
