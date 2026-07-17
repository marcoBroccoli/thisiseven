# Phase 2 Calendar Reliability And Today View Design

## Goal

Make Household Command Center useful as a daily operating surface by keeping approved items synchronized with Google Calendar and surfacing the items that need attention today.

## Scope

Phase 2 stays local-first. It does not add Supabase, bunq, Gmail send scopes, or background daemons. The app continues to use local JSON storage and explicit user actions, while improving Calendar correctness and the first-run workflow.

## Approach

The app stores a lightweight snapshot of the Calendar payload last written for each approved draft. When a user edits an approved item, the draft becomes a Calendar update candidate instead of creating a duplicate event. A new Calendar update path patches the existing Google Calendar event and refreshes the local snapshot.

Manual Calendar sync compares the stored snapshot with the current remote Calendar event. If the remote event was deleted or changed outside the app, the draft moves into external-change review with a readable summary of changed fields. The user can keep the app version, accept the Calendar version, recreate a deleted event, or mark the item done.

The Today view becomes the default section. It groups visible local drafts into overdue, due today, waiting, needs reply, and Calendar attention. This is intentionally a review dashboard, not another database layer.

## Core Data

- `CalendarEventSnapshot`: title, due date, notes, event URL, and captured time.
- `InboxDraft.calendarLastSyncedSnapshot`: last app-written Calendar state.
- `InboxDraft.calendarExternalSnapshot`: current remote Calendar state when external drift is detected.
- `InboxDraftStatus.calendarUpdateRequired`: approved app fields changed locally and need to be pushed to Calendar.

## App Workflow

1. User approves a draft.
2. App creates a Google Calendar event and stores a local Calendar snapshot.
3. User edits an approved draft.
4. Draft becomes `calendarUpdateRequired`.
5. User clicks Sync Calendar.
6. App patches the existing Google Calendar event and refreshes the snapshot.
7. User clicks Check Calendar.
8. App fetches remote event details and marks external drift with field-level summary if remote data differs.

## Today View

Today groups actionable items without duplicating data:

- Calendar Attention: retry, update required, external change.
- Overdue: visible items due before today.
- Due Today: visible items due today.
- Waiting: visible items marked waiting.
- Needs Reply: visible items marked needs reply or detected by email intelligence.

Closed items (`done`, `notHousehold`, approved/rejected without attention) are hidden from Today.

## Error Handling

Calendar update failures move the draft to `calendarRetryRequired` with the error message. Missing event IDs fall back to Calendar create. Deleted events remain `changedExternally` until the user recreates them, accepts that they are done, or rejects the item.

## Testing

Add core tests for Calendar update, external drift diffing, conflict resolution, and Today grouping. Add Google API tests for PATCH payloads and remote snapshot parsing. Run the full Swift test suite and launcher build check.
