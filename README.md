# Household Command Center

Native SwiftUI macOS prototype for a couple to manage shared household work through Gmail-derived drafts and Google Calendar approval.

## What Is Implemented

- A Swift package with:
  - `HouseholdCore`: testable domain models and workflow services.
  - `HouseholdCommandCenter`: SwiftUI macOS app target.
- Inbox First Mac UI:
  - Today view as the default operating surface for due work, replies, waiting items, and Calendar sync problems.
  - Gmail discovery import action with optional `HouseholdTodo` label support.
  - Organized draft inbox grouped by urgency, replies, bills, Calendar sync, Calendar items, low-priority items, and review.
  - Selected draft editor, owner/area assignment, amount, due date, AI evidence, and approval controls.
  - Local email intelligence for urgency, tagging, suggested replies, and reminder timing.
  - Daily-use actions for Waiting, Done, Needs Reply, Reply Done, Not Household, and Ignore Sender.
  - Safe Gmail reply workflow with editable reply drafts, copy, Gmail compose handoff, source email lookup, and manual sent tracking.
  - Quick Add for manual household items.
  - Bills, Reminders, Weekly Review, Banking Candidates, Areas, and Settings sections.
  - Connection/status panel for Gmail, Google Calendar, local storage, email intelligence, and staged banking.
- Core workflow:
  - Gmail label-first import with automatic household-email discovery fallback.
  - Lightweight local JSON storage for drafts, user edits, approval state, Google Calendar mappings, ignored senders, and reply text.
  - Gmail imports merge into local state instead of replacing edited or approved items.
  - Dismissed/not-household drafts stay out of the working inbox, and ignored senders are skipped on future imports.
  - Calendar readiness states for due-date gaps, ready-to-approve items, scheduled events, retry failures, and external changes.
  - Calendar approval uses per-item reminder timing from email intelligence instead of a single fixed reminder rule.
  - Approved local edits become Calendar sync-needed items instead of creating duplicate events.
  - Existing Google Calendar events can be patched from the app.
  - Calendar sync can fetch remote event details and show field-level external-change summaries.
  - External Calendar conflicts can be resolved by keeping the app record, accepting the Calendar version, recreating the event, or marking the item done.
  - Manual Calendar sync stores a local last-sync timestamp.
  - Gmail reply composer builds prefilled Gmail compose URLs without requiring Gmail send or draft-write scopes.
  - Google OAuth authorization URL factory for desktop/test-user flows.
  - Live Google desktop OAuth test flow with local loopback callback and Keychain token storage.
  - Gmail label lookup, Gmail search discovery, Gmail metadata mapping, real Calendar event insertion, and Calendar event payload construction.
  - AI extraction contract with low-confidence action fields blanked.
  - Approval writes a Google Calendar event through a mockable client.
  - Calendar failure retry state, rejection, external deletion reconciliation, and lightweight external-change resolution.
  - Dashboard summaries for bills due soon, weekly review items, and area workloads.
- Supabase starter schema and Edge Function stubs in `supabase/`.

The app uses local heuristics and a demo AI extractor so it can run without an extraction backend. Gmail import and Calendar approval can run in either demo mode or live Google test mode from Settings.

## Screens

- **Today**: due, overdue, waiting, reply-needed, and Calendar-attention items for daily review.
- **Inbox**: organized approval queue, manual Quick Add, selected draft editor, daily triage actions, suggested replies, and approve/reject controls.
- **Bills**: open finance obligations due in the next seven days.
- **Reminders**: Calendar readiness groups for missing due dates, ready approvals, scheduled events, retries, and external changes.
- **Review**: unassigned items, Calendar retry failures, externally changed Calendar events, and last Calendar sync status.
- **Banking**: read-only candidates that can later be matched against bunq transactions.
- **Areas**: active workload and open obligation total by household area.
- **Settings**: Google OAuth scopes, local-first backend notes, local storage path, ignored-sender count, and demo-mode integration notes.

## Run

```bash
swift test
./scripts/run-mac-app.sh
```

`swift run HouseholdCommandCenter` builds a command-line executable and may stay running without activating a visible macOS window. The launcher script wraps the executable in a temporary `.app` bundle at `.build/HouseholdCommandCenter.app` and opens it through LaunchServices.

If Xcode 26 opens the package, use the `HouseholdCommandCenter` executable scheme. If the window does not come forward from Xcode, run the launcher script above.

The package uses Swift tools 5.10 language mode intentionally. Xcode 26 Swift 6.2 crashed while compiling the SwiftUI view in Swift 6 language mode; Swift 5.10 mode builds the same app cleanly.

## Google Test Path

1. Create a Google Cloud OAuth client with application type `Desktop app`.
2. Add `house.marcansu@gmail.com` as a test user in Google Auth Platform.
3. Enable Gmail API and Google Calendar API.
4. Add scopes:
   - `https://www.googleapis.com/auth/gmail.readonly`
   - `https://www.googleapis.com/auth/calendar.events`
   - `openid email profile`
5. Optionally create a Gmail label named `HouseholdTodo` for hand-picked emails.
6. You can also skip labeling; live import searches recent likely household emails such as bills, invoices, renewals, reminders, and appointments.
7. Launch the app with `./scripts/run-mac-app.sh`.
8. Open **Settings**, paste the Desktop app client ID and Desktop app client secret, leave Calendar ID as `primary`, and click **Connect Google**.
9. In the browser, sign in as `house.marcansu@gmail.com` and approve the test app.
10. Return to the app and click **Discover Gmail Emails**.
11. For emails that need a response, edit the reply draft, click **Open Compose**, send from Gmail, then click **Mark Sent** in the app.
12. Select a draft with a due date and click **Approve to Calendar**.
13. Open Google Calendar for `house.marcansu@gmail.com` and verify the event was created.

The app stores the Desktop client ID and Calendar ID in user defaults. OAuth tokens and the Desktop client secret are stored in macOS Keychain after a successful connection. Do not commit the downloaded OAuth JSON or paste the secret into source files.

Gmail read scopes are restricted for public apps. Keep this as a private test-user OAuth flow until verification requirements are handled. The current reply flow deliberately does not request Gmail send or draft-write scopes; Gmail remains the place where the user reviews and sends the message.

## Local Storage

Until the product behavior is final, household state is stored in a local JSON file instead of Supabase. The file contains imported drafts, edits, triage state, approval/rejection status, Google Calendar event mappings, Calendar sync snapshots, ignored senders, per-draft reply text, and reply workflow state.

The path is shown in **Settings > Local Storage**. On a typical macOS install it is:

```text
~/Library/Application Support/HouseholdCommandCenter/local-state.json
```

Deleting that file resets the local household inbox to the demo seed on the next launch. Gmail discovery can then repopulate live drafts.

The same local file stores the last manual Calendar sync timestamp shown in **Review** and **Settings**.

## Supabase Later

When the local workflow is stable, start with `supabase/schema.sql`, then deploy the function stubs:

```bash
supabase db push
supabase functions deploy import-householdtodo
supabase functions deploy approve-calendar-event
```

The schema is intentionally narrow: Supabase stores household context, approval state, finance obligation metadata, audit events, and Google object mappings. Google Calendar remains canonical for todos/reminders.

# thisiseven
