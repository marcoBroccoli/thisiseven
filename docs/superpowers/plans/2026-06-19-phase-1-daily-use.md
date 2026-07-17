# Phase 1 Daily Use Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Phase 1 by making repeated daily Gmail imports, reply handling, and Calendar recovery feel usable with local-only state.

**Architecture:** Extend `InboxDraft` with lightweight triage and reply workflow fields. Extend `LocalHouseholdState` with ignored sender rules and merge filtering. Add store actions and UI controls for not household, waiting, done, reply status, sender ignore, Calendar retry, and external-change resolution.

**Tech Stack:** Swift, SwiftUI, Foundation Codable, local JSON persistence, Swift Package tests.

---

### Task 1: Local Triage And Reply State

- Add `DraftTriageState` and `ReplyWorkflowStatus`.
- Add optional fields to `InboxDraft` for backward-compatible JSON decode.
- Add tests that classify done/not-household as closed, waiting as open, and reply status as persisted.

### Task 2: Sender Ignore And Import Preservation

- Add ignored sender rules to `LocalHouseholdState`.
- Merge imports without re-adding ignored senders.
- Preserve existing rejected/not-household/done/waiting decisions.

### Task 3: App Actions

- Add actions in `DemoHouseholdStore`: mark not household, mark done, mark waiting, needs reply, reply done, ignore sender, retry Calendar, resolve external change.
- Persist after each action.
- Update copy/open Gmail to set reply status.

### Task 4: UI

- Add detail controls for triage and reply workflow.
- Show ignored sender count in Settings.
- Add Waiting bucket and hide Done/Not Household from active inbox buckets.
- Add Calendar retry/external resolution buttons.

### Task 5: Verification

- Run `swift test`.
- Run `./scripts/run-mac-app.sh --build-only`.
- Relaunch the app.
