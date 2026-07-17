# Gmail Reply Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit suggested replies, open prefilled Gmail compose windows, and track reply completion locally without Gmail write/send scopes.

**Architecture:** Add a pure `HouseholdCore` Gmail compose URL builder and reply status helper logic. Wire app store actions to mark local reply states as drafted, copied, opened, sent manually, or done. Keep Gmail write APIs out of scope.

**Tech Stack:** Swift, SwiftUI, Foundation `URLComponents`, local JSON persistence, Swift Package tests.

---

### Task 1: Reply Status Semantics

**Files:**
- Modify: `Sources/HouseholdCore/Models.swift`
- Test: `Tests/HouseholdCoreTests/GmailReplyWorkflowTests.swift`

- [ ] Add `drafted` and `sentManually` cases to `ReplyWorkflowStatus`.
- [ ] Add `requiresReplyAction` so `needsReply`, `drafted`, `copied`, and `openedInGmail` require attention, while `none`, `sentManually`, and `done` do not.
- [ ] Add tests for the attention behavior.

### Task 2: Gmail Compose URL Builder

**Files:**
- Create: `Sources/HouseholdCore/GmailReplyComposer.swift`
- Test: `Tests/HouseholdCoreTests/GmailReplyWorkflowTests.swift`

- [ ] Add `GmailReplyDraft` with `to`, `subject`, and `body`.
- [ ] Add `GmailReplyComposer.replyDraft(for:body:)`.
- [ ] Add `GmailReplyComposer.composeURL(for:)`.
- [ ] Parse sender values like `Name <person@example.com>` into `person@example.com`.
- [ ] Add tests for recipient parsing, subject `Re:` handling, and URL query fields.

### Task 3: Today Reply Grouping

**Files:**
- Modify: `Sources/HouseholdCore/TodayReviewModel.swift`
- Test: `Tests/HouseholdCoreTests/TodayReviewTests.swift`

- [ ] Use `ReplyWorkflowStatus.requiresReplyAction` for explicit reply states.
- [ ] Do not surface `sentManually` or `done` in Needs Reply, even when email intelligence detects reply language.
- [ ] Add a test proving manually sent replies leave Today.

### Task 4: App Store Actions

**Files:**
- Modify: `Sources/HouseholdCommandCenter/DemoHouseholdStore.swift`

- [ ] Mark a reply as `drafted` when the user edits non-empty reply text.
- [ ] Add `openSelectedReplyInGmailCompose()`.
- [ ] Keep `openSelectedEmailInGmail()` as a search/find action.
- [ ] Add `markSelectedReplySentManually()`.
- [ ] Persist after every reply state transition.

### Task 5: SwiftUI Reply Controls

**Files:**
- Modify: `Sources/HouseholdCommandCenter/HouseholdRootView.swift`

- [ ] Add buttons for Copy Reply, Open Compose, Find Email, Mark Sent, and Reply Done.
- [ ] Show the expanded reply states in the reply badge.
- [ ] Keep controls disabled when they do not apply.

### Task 6: Docs And Verification

**Files:**
- Modify: `README.md`

- [ ] Document safe Gmail compose handoff and no auto-send.
- [ ] Run `swift test`.
- [ ] Run `./scripts/run-mac-app.sh --build-only`.
- [ ] Relaunch with `./scripts/run-mac-app.sh`.
