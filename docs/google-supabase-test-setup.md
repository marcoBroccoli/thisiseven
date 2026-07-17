# Google And Supabase Test Setup

## OAuth

Use a Google Cloud desktop OAuth client for local Mac testing. Keep the consent screen in testing mode and add only test users.

Required test scopes:

- Gmail labeled-message read: `https://www.googleapis.com/auth/gmail.readonly`
- Calendar event write: `https://www.googleapis.com/auth/calendar.events`
- User identity: `openid email profile`

The app first imports messages labeled `HouseholdTodo` when that label exists. If the label is missing, it searches recent Gmail for likely household work such as bills, invoices, renewals, reminders, appointments, repairs, school/admin messages, and subscriptions. Do not request full mailbox mutation scopes for v1.

`HouseholdCore` now includes deterministic Google integration foundations:

- `GoogleOAuthPKCE` generates desktop OAuth PKCE challenges.
- `GoogleOAuthRequestFactory` builds the installed-app authorization URL.
- `GoogleOAuthTokenRequestFactory` builds token exchange and refresh requests with an optional client secret.
- `GoogleGmailAPIClient` resolves the `HouseholdTodo` label when available, otherwise uses a read-only Gmail search query to discover likely household messages.
- `GoogleCalendarAPIClient` creates approved events in Google Calendar and checks whether existing events are present or deleted.
- `GmailMessageMapper` converts Gmail metadata responses into `SourceEmail`.
- `GoogleCalendarPayloadFactory` converts approved household drafts into Calendar API event payloads.

The macOS target adds the live local test flow:

- Paste the Desktop app client ID and client secret in **Settings**.
- Click **Connect Google**.
- The app opens Google sign-in and listens on `http://127.0.0.1:<random-port>/oauth/callback`.
- Tokens are stored in macOS Keychain.
- **Discover Gmail Emails** uses live Gmail when connected and demo Gmail when disconnected.
- Calendar ID defaults to `primary`, which writes to the signed-in account's primary Google Calendar.
- **Approve to Calendar** uses live Google Calendar when connected and demo Calendar when disconnected.

Do not commit the downloaded OAuth JSON or put the client secret in source code. The app stores the client secret in macOS Keychain after a successful connection because this OAuth client requires it for token exchange.

## Data Flow

1. User optionally labels an email `HouseholdTodo`.
2. Gmail import function fetches labeled messages, or searches likely household messages when the label is absent.
3. Import creates an `inbox_drafts` row with source email metadata.
4. AI extraction writes title, due date, amount, owner, area, evidence, and confidence.
5. Mac app shows the draft for human approval.
6. Approval creates a Google Calendar event.
7. Supabase stores the Google Calendar event ID and audit event.

## AI Guardrail

The core model treats extraction confidence below `0.60` as non-actionable. Title can still be suggested, but due date, amount, owner, and area remain blank until a person fills them in.

## Local Feature Layer

Manual household items are created with `ManualDraftFactory` and enter the same pending approval flow as Gmail-derived drafts. The dashboard layer groups:

- finance obligations due in the next seven days,
- weekly review items requiring human attention,
- active work and open obligation total by household area.

## Public Release Note

Gmail restricted scopes can require Google verification and potentially a security assessment if restricted data is stored or transmitted. Keep the first Gmail integration private and test-user only.
