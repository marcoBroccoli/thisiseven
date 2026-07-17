# Calendar Reliability And Today View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make approved household items update their existing Google Calendar events and make Today the default daily review surface.

**Architecture:** Extend the Calendar abstraction with update and snapshot reads. Store local Calendar snapshots on drafts, use them to mark local update-needed state and external drift, and add a Today review model that groups actionable local drafts. Keep all state local JSON and all Calendar writes user-triggered.

**Tech Stack:** Swift, SwiftUI, Foundation Codable, Google Calendar REST API, Swift Package tests.

---

### Task 1: Calendar Snapshot And Status Model

**Files:**
- Modify: `Sources/HouseholdCore/CalendarIntegration.swift`
- Modify: `Sources/HouseholdCore/Models.swift`
- Test: `Tests/HouseholdCoreTests/CalendarReliabilityTests.swift`

- [ ] Add `CalendarEventSnapshot` with `title`, `dueDate`, `notes`, `url`, and `capturedAt`.
- [ ] Add `InboxDraftStatus.calendarUpdateRequired`.
- [ ] Add optional `calendarLastSyncedSnapshot` and `calendarExternalSnapshot` to `InboxDraft`.
- [ ] Add tests proving older draft JSON remains decodable when snapshot fields are absent.

### Task 2: Calendar Update And Drift Detection

**Files:**
- Modify: `Sources/HouseholdCore/CalendarIntegration.swift`
- Modify: `Sources/HouseholdCore/HouseholdApprovalService.swift`
- Test: `Tests/HouseholdCoreTests/CalendarReliabilityTests.swift`

- [ ] Add `CalendarClient.updateEvent(id:with:)` and `CalendarClient.eventSnapshot(for:)`.
- [ ] Add `HouseholdApprovalService.syncExistingCalendarEvent`.
- [ ] Store snapshots after create and update.
- [ ] Detect remote snapshot differences during reconcile and summarize changed fields.
- [ ] Add tests for successful update, update failure, deleted remote event, and modified remote event.

### Task 3: Google Calendar API Support

**Files:**
- Modify: `Sources/HouseholdCore/GoogleCalendarAPIClient.swift`
- Modify: `Sources/HouseholdCore/GoogleAPIModels.swift`
- Test: `Tests/HouseholdCoreTests/GoogleIntegrationTests.swift`

- [ ] Add PATCH support against `/calendar/v3/calendars/{calendarID}/events/{eventID}?sendUpdates=none`.
- [ ] Parse Google event `summary`, `description`, `start.dateTime`, `htmlLink`, and `status` into `CalendarEventSnapshot`.
- [ ] Add tests for PATCH request body and remote snapshot parsing.

### Task 4: Today Review Model

**Files:**
- Create: `Sources/HouseholdCore/TodayReviewModel.swift`
- Test: `Tests/HouseholdCoreTests/TodayReviewTests.swift`

- [ ] Add `TodayReviewSection` and `TodayReviewModel`.
- [ ] Group visible drafts into Calendar Attention, Overdue, Due Today, Waiting, and Needs Reply.
- [ ] Add tests for grouping order, hidden closed items, and no duplicate items across sections.

### Task 5: App Store Actions

**Files:**
- Modify: `Sources/HouseholdCommandCenter/DemoHouseholdStore.swift`

- [ ] Mark approved drafts as `calendarUpdateRequired` when edited locally.
- [ ] Add `syncSelectedCalendarUpdate`.
- [ ] Add `acceptSelectedCalendarVersion`.
- [ ] Add `recreateSelectedCalendarEvent`.
- [ ] Expose `todaySections` from `TodayReviewModel`.

### Task 6: SwiftUI Today And Calendar Controls

**Files:**
- Modify: `Sources/HouseholdCommandCenter/HouseholdRootView.swift`

- [ ] Add `HouseholdSection.today` as the first/default section.
- [ ] Add `TodayView` with grouped cards and Calendar action buttons.
- [ ] Add badges and detail controls for `calendarUpdateRequired`.
- [ ] Update external-change controls to include Accept Calendar Version and Recreate Event.

### Task 7: Docs And Verification

**Files:**
- Modify: `README.md`

- [ ] Document Phase 2 behavior in What Is Implemented and Screens.
- [ ] Run `swift test`.
- [ ] Run `./scripts/run-mac-app.sh --build-only`.
- [ ] Relaunch with `./scripts/run-mac-app.sh`.
