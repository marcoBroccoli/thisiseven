# Feature-Rich Integrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the prototype into a richer local app with real Google/Supabase integration seams ready for credentials.

**Architecture:** Keep `HouseholdCore` as the testable domain and integration layer. Keep the SwiftUI target as a demo-backed app that exercises production-shaped protocols without requiring secrets.

**Tech Stack:** Swift Package Manager, SwiftUI/AppKit, XCTest, Foundation networking contracts, Supabase SQL/Edge Function stubs.

---

### Task 1: Google Integration Foundations

**Files:**
- Create: `Sources/HouseholdCore/GoogleOAuth.swift`
- Create: `Sources/HouseholdCore/GoogleAPIModels.swift`
- Test: `Tests/HouseholdCoreTests/GoogleIntegrationTests.swift`

- [ ] Add tests for OAuth URL construction, Gmail metadata mapping, and Calendar payload creation.
- [ ] Implement `GoogleOAuthConfiguration`, `GoogleOAuthRequestFactory`, `GmailMessageMapper`, and `GoogleCalendarPayloadFactory`.
- [ ] Run `swift test`.

### Task 2: Local Feature State

**Files:**
- Modify: `Sources/HouseholdCore/Models.swift`
- Create: `Sources/HouseholdCore/HouseholdDashboard.swift`
- Test: `Tests/HouseholdCoreTests/HouseholdDashboardTests.swift`

- [ ] Add tests for manual draft creation, bills due soon, weekly review grouping, and area load summaries.
- [ ] Implement `ManualDraftFactory` and `HouseholdDashboard`.
- [ ] Run `swift test`.

### Task 3: Richer SwiftUI App

**Files:**
- Modify: `Sources/HouseholdCommandCenter/DemoHouseholdStore.swift`
- Modify: `Sources/HouseholdCommandCenter/DemoSeedData.swift`
- Modify: `Sources/HouseholdCommandCenter/HouseholdRootView.swift`

- [ ] Add app sections for Inbox, Bills, Weekly Review, Areas, and Settings.
- [ ] Add manual item creation using the tested core factory.
- [ ] Show richer connection settings and integration readiness states.
- [ ] Run `swift test` and `swift build`.

### Task 4: Docs

**Files:**
- Modify: `README.md`
- Modify: `docs/google-supabase-test-setup.md`

- [ ] Document the new screens and integration seams.
- [ ] Keep the real-credential setup clear and private-test-user focused.
- [ ] Run final verification.
