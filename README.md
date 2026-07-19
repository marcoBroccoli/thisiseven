# Household Command Center

Native SwiftUI iPhone app for a couple to manage shared household work through Gmail-derived drafts and Google Calendar approval. It is local-first while the product workflow is being finalized.

## What Is Implemented

- A Swift package with:
  - `HouseholdCore`: testable domain models and workflow services.
  - `HouseholdCommandCenter`: SwiftUI macOS development target.
  - `HouseholdCommandCenterMobile`: iPhone SwiftUI app target in `HouseholdCommandCenterMobile.xcodeproj`.
- Inbox First mobile UI:
  - Today view as the default operating surface for due work, replies, waiting items, and Calendar sync problems.
  - Gmail discovery import action with optional `HouseholdTodo` label support.
  - Organized draft inbox grouped by urgency, replies, bills, Calendar sync, Calendar items, low-priority items, and review.
  - Selected draft editor, owner/area assignment, amount, due date, AI evidence, and approval controls.
  - Local email intelligence for urgency, tagging, suggested replies, and reminder timing.
  - Daily-use actions for Waiting, Done, Needs Reply, Reply Done, Not Household, and Ignore Sender.
  - True local deferment for unapproved work: choose a return time without changing the original due date or Google Calendar.
  - Safe Gmail reply workflow with editable reply drafts, Gmail Draft save/update, compose handoff, source email lookup, and manual sent tracking.
  - Quick Add for manual household items.
  - Manual recurring tasks with weekly, fortnightly, monthly, or quarterly schedules; chores can leave amount blank.
  - Bills, Reminders, Weekly Review, Payments, Areas, and Settings sections.
  - Connection/status panel for Gmail, Google Calendar, local storage, email intelligence, and local-first banking reconciliation.
- Core workflow:
  - Gmail label-first import with automatic household-email discovery fallback.
  - Lightweight local JSON storage for drafts, user edits, approval state, Google Calendar mappings, ignored senders, reply text, imported transactions, and payment-match decisions.
  - Gmail imports merge into local state instead of replacing edited or approved items.
  - Dismissed/not-household drafts stay out of the working inbox, and ignored senders are skipped on future imports.
  - Calendar readiness states for due-date gaps, ready-to-approve items, scheduled events, retry failures, and external changes.
  - Calendar approval uses per-item reminder timing from email intelligence instead of a single fixed reminder rule.
  - Local iPhone notifications can remind the household about open, unapproved work without duplicating Google Calendar alerts for approved items.
  - Approved local edits become Calendar sync-needed items instead of creating duplicate events.
  - Existing Google Calendar events can be patched from the app.
  - Calendar sync can fetch remote event details and show field-level external-change summaries.
  - External Calendar conflicts can be resolved by keeping the app record, accepting the Calendar version, recreating the event, or marking the item done.
  - Manual Calendar sync stores a local last-sync timestamp.
  - Gmail reply composer can create or update a Gmail Draft, while sending remains a deliberate action in Gmail.
  - Google OAuth authorization URL factory for desktop/test-user flows.
  - Live Google desktop OAuth test flow with local loopback callback and Keychain token storage.
  - Gmail label lookup, Gmail search discovery, Gmail metadata mapping, real Calendar event insertion, and Calendar event payload construction.
  - AI extraction contract with low-confidence action fields blanked.
  - Approval writes a Google Calendar event through a mockable client.
  - Calendar failure retry state, rejection, external deletion reconciliation, and lightweight external-change resolution.
  - Read-only local CSV statement import and deterministic matching of outgoing transactions to Gmail-derived household obligations.
  - Dashboard summaries for bills due soon, weekly review items, and area workloads.
- Supabase starter schema and Edge Function stubs in `supabase/`.

The app uses local heuristics and a demo AI extractor so it can run without an extraction backend. Gmail import and Calendar approval can run in either demo mode or live Google test mode from Settings.

## Screens

- **Today**: due, overdue, waiting, reply-needed, and Calendar-attention items for daily review.
- **Inbox**: organized approval queue, manual Quick Add, selected draft editor, daily triage actions, suggested replies, and approve/reject controls.
- **Bills**: open finance obligations due in the next seven days.
- **Reminders**: Calendar readiness groups for missing due dates, ready approvals, scheduled events, retries, external changes, and local app reminder controls.
- **Review**: unassigned items, Calendar retry failures, externally changed Calendar events, and last Calendar sync status.
- **Payments**: import a local CSV statement, confirm or dismiss suggested matches, and manually match an outgoing payment. No banking credentials or payment initiation.
- **Areas**: active workload and open obligation total by household area.
- **Settings**: Google OAuth scopes, local-first backend notes, local storage path, ignored-sender count, and demo-mode integration notes.

## Run On iPhone

```bash
swift test
open HouseholdCommandCenterMobile.xcodeproj
```

In Xcode, select the `HouseholdCommandCenterMobile` scheme, choose an iPhone Simulator or connected iPhone, then press Run. The app target is iPhone-only and requires iOS 17 or later.

The legacy Mac target remains available for local development:

```bash
./scripts/run-mac-app.sh
```

The project uses Swift 5.10 language mode intentionally. Xcode 26 Swift 6.2 crashed while compiling the SwiftUI view in Swift 6 language mode; Swift 5.10 mode builds the same app cleanly.

## Google Test Path

1. Create a Google Cloud OAuth client with application type `iOS` and bundle ID `local.household-command-center.ios`.
2. Add `house.marcansu@gmail.com` as a test user in Google Auth Platform.
3. Enable Gmail API and Google Calendar API.
4. Add scopes:
   - `https://www.googleapis.com/auth/gmail.readonly`
   - `https://www.googleapis.com/auth/gmail.compose`
   - `https://www.googleapis.com/auth/calendar.events`
   - `openid email profile`
5. Optionally create a Gmail label named `HouseholdTodo` for hand-picked emails.
6. You can also skip labeling; live import searches recent likely household emails such as bills, invoices, renewals, reminders, and appointments.
7. Copy the iOS client ID and the **iOS URL scheme** from Google Cloud into [MobileApp/Config/Google.xcconfig](/Users/marcobroccoli/Documents/PersonalTodo/MobileApp/Config/Google.xcconfig). The iOS URL scheme is the reverse client ID shown in the Google console.
8. Open `HouseholdCommandCenterMobile.xcodeproj` and run the app on an iPhone Simulator or device. There is no iOS client secret.
9. Open **Areas > Settings**, confirm the iOS client ID and Calendar ID (`primary` is fine for the signed-in account), then tap **Connect Google**.
10. In the browser, sign in as `house.marcansu@gmail.com` and approve the test app.
11. Return to the app and tap **Discover Gmail Emails**.
12. For emails that need a response, edit the reply draft, use **Save Gmail Draft** or **Open Compose**, review and send from Gmail, then tap **Mark Sent** in the app.
13. Select a draft with a due date and tap **Approve to Calendar**.
14. Open Google Calendar for `house.marcansu@gmail.com` and verify the event was created.

The app stores the iOS client ID and Calendar ID in user defaults. Google Sign-In manages the iOS session; no client secret is used or stored. Do not commit the downloaded OAuth JSON or paste secrets into source files.

Gmail read and compose scopes are restricted for public apps. Keep this as a private test-user OAuth flow until verification requirements are handled. The app creates or updates drafts only; Gmail remains the place where the user reviews and sends the message.

## Local Storage

Until the product behavior is final, household state is stored in a local JSON file instead of Supabase. The file contains imported drafts, edits, triage state, approval/rejection status, Google Calendar event mappings, Calendar sync snapshots, ignored senders, per-draft reply text, reply workflow state, imported bank-statement transactions, and payment-match decisions.

The path is shown in **Settings > Local Storage**. On an iPhone, it is in the app's private Application Support container. The legacy Mac target uses:

```text
~/Library/Application Support/HouseholdCommandCenter/local-state.json
```

Deleting that file resets the local household inbox to the demo seed on the next launch. Gmail discovery can then repopulate live drafts.

The same local file stores the last manual Calendar sync timestamp shown in **Review** and **Settings**.

## App Reminders

Open **Reminders** and use **Enable alerts** once to grant iPhone notification permission. The app schedules reminders for open work using the existing urgency policy and refreshes those scheduled alerts after local changes. Approved Calendar events retain their Google Calendar reminders and are intentionally excluded from local alerts.

## Defer Work

From an unapproved item in **Inbox**, choose **Defer** and select Later today, Tomorrow morning, Next week, or a custom date and time. Deferred work leaves Today, active Inbox groups, bills, payment matching, Calendar readiness, and ordinary local due-date alerts until its return time. The task's original due date is preserved. A local “Back on your list” notification is scheduled for the return time, and **Resume now** restores the item immediately.

## Recurring Todos

Open **Add household item**, enter a task such as `Wash the dog`, choose its first due date, and select **Repeat**. Amount is optional, so chores have no cost. After the normal approval step, the app creates a recurring Google Calendar event using the matching weekly, fortnightly, monthly, or quarterly rule. The event keeps its Google Calendar reminders.

## Payments CSV Import

Open **Payments**, choose **Import CSV**, and select a statement export from your bank. The importer accepts comma-, semicolon-, or tab-separated files with a date and either an `Amount`/`Bedrag` column or separate debit and credit columns. It recognizes common English and Dutch headers and European decimal amounts such as `-42,50`.

Imported transactions stay on this Mac. The app only proposes outgoing-payment matches for open household items with an amount; confirming a match never initiates a payment or marks the household item done automatically. Use **Load sample** to explore the matching flow without a statement export.

## Supabase Later

When the local workflow is stable, start with `supabase/schema.sql`, then deploy the function stubs:

```bash
supabase db push
supabase functions deploy import-householdtodo
supabase functions deploy approve-calendar-event
```

The schema is intentionally narrow: Supabase stores household context, approval state, finance obligation metadata, audit events, and Google object mappings. Google Calendar remains canonical for todos/reminders.

# thisiseven
