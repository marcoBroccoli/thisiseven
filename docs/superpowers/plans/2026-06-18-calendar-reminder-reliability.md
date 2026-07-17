# Calendar Reminder Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Calendar approval and reminders more reliable while keeping state local and lightweight.

**Architecture:** Add a core readiness evaluator that turns each draft into a clear Calendar state. Pass email-intelligence reminder timing into Calendar event creation. Persist the last manual Calendar sync timestamp in the local JSON store.

**Tech Stack:** Swift, Foundation `Codable`, Swift Package tests, SwiftUI.

---

### Task 1: Calendar Readiness Core

**Files:**
- Create: `Sources/HouseholdCore/CalendarReadiness.swift`
- Test: `Tests/HouseholdCoreTests/CalendarReadinessTests.swift`

- [ ] Write failing tests for `needsDueDate`, `readyToApprove`, `scheduled`, `retryRequired`, `externalChange`, and `rejected`.
- [ ] Implement `CalendarReadinessState`, `CalendarReadiness`, and `CalendarReadinessEvaluator`.
- [ ] Verify targeted tests pass.

### Task 2: Calendar Approval Reminder Minutes

**Files:**
- Modify: `Sources/HouseholdCore/HouseholdApprovalService.swift`
- Modify: `Sources/HouseholdCommandCenter/DemoHouseholdStore.swift`
- Test: `Tests/HouseholdCoreTests/HouseholdWorkflowTests.swift`

- [ ] Write a failing test proving approval uses supplied reminder minutes.
- [ ] Add a `reminderMinutesBefore` parameter to approval while preserving the existing default.
- [ ] Pass `EmailIntelligenceAnalyzer` reminder minutes from the Mac store.
- [ ] Verify targeted tests pass.

### Task 3: Persist Last Calendar Sync

**Files:**
- Modify: `Sources/HouseholdCore/HouseholdLocalStore.swift`
- Modify: `Sources/HouseholdCommandCenter/DemoHouseholdStore.swift`
- Test: `Tests/HouseholdCoreTests/HouseholdLocalStoreTests.swift`

- [ ] Write a failing test that saves/loads `lastCalendarSyncAt`.
- [ ] Add optional timestamp to local state.
- [ ] Set it after manual Calendar sync.
- [ ] Verify targeted tests pass.

### Task 4: UI Wiring And Verification

**Files:**
- Modify: `Sources/HouseholdCommandCenter/HouseholdRootView.swift`
- Modify: `README.md`

- [ ] Group Reminders by readiness state.
- [ ] Show last Calendar sync in Review and Settings.
- [ ] Run `swift test`.
- [ ] Run `./scripts/run-mac-app.sh --build-only`.
