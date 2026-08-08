# evend API contract (v1)

Base URL: `http://localhost:8091` (sim) / `http://even-api.home` (LAN).
All `/v1/*` require auth (see below). WebSocket: `ws://` / `wss://` on the same host.
JSON snake_case. Money in euro cents (int). Dates `YYYY-MM-DD`, timestamps RFC3339.
Errors: `{"error": {"code": "string", "message": "human text"}}` with 4xx/5xx.

### Auth on `/v1/*`
- REST: `Authorization: Bearer <gotrue access token>`.
- WebSocket upgrade (`GET /v1/ws/household`): same Bearer header **or**
  `?access_token=<gotrue access token>` (for clients that cannot set upgrade headers).

## Auth (proxied to GoTrue, standard Supabase auth API)
- `POST /auth/token?grant_type=id_token` `{provider:"apple", id_token, nonce}`
- `POST /auth/token?grant_type=password` `{email, password}` (debug accounts)
- `POST /auth/signup` `{email, password}`
- `POST /auth/token?grant_type=refresh_token` `{refresh_token}`
- `POST /auth/logout`
GoTrue mounts these under its own `/token` etc.; evend strips the `/auth` prefix.

## Objects
```
member      {id, display_name, color: "#RRGGBB", is_me, has_avatar}
            // legacy "clay"/"teal" still accepted on write; responses normalize to hex
            // has_avatar — photo on house server; fetch via GET /v1/members/{id}/avatar
household   {id, name, invite_code, members: [member]}
week        {id, index, started_on, closed_at?}          // index: 1,2,3…
task        {id, title, section: "chore"|"admin", owner_member_id, weight: 1|2|3,
             recurrence: "none"|"daily"|"every_2_days"|"weekly", due_on?,
             recurrence_until?, recurrence_count?,
             done, done_by_member_id?, meta_line, google_event_url?,
             calendar_sync_state: "not_scheduled"|"synced"|"external_changed"|
             "external_deleted"|"retry_required", calendar_last_synced_at?,
             calendar_last_error?}                         // done = completion in open week
draft       {id, from_label, subject, summary?, urgency: 1|2|3, title,
             owner_member_id, amount_cents?, due_on?,
             reminder: "on_day"|"1_day"|"3_days"|"1_week", status, created_by_member_id,
             needs_reply, suggested_reply?, reply_text?,
             reply_status: "none"|"drafted"|"opened_in_gmail"|"sent_manually"|"done"}
expense     {id, title, amount_cents, paid_by_member_id, incurred_on, settled}
settlement  {id, from_member_id, to_member_id, amount_cents, created_at}
appreciation{id, from_member_id, to_member_id, body?, said}
trade       {id, task_id, task_title, from_member_id, to_member_id, accepted}
```

## Endpoints
- `GET  /healthz` → `{ok:true}` (no auth)
- `GET  /v1/me` → `{user_id, member?, household?, week?}` — member/household
  null until onboarded; drives app routing.
- `PATCH /v1/me` `{display_name?, color?}` → member — update the caller's
  profile (membership required). At least one field required. `display_name`
  trimmed, 1–40 chars. `color` is `#RRGGBB` (any sRGB); legacy `clay`|`teal`
  accepted and stored as terracotta / pine hex. Partners may share a color.
- `PUT /v1/me/avatar` `multipart/form-data` field `avatar` (JPEG or PNG) →
  member — store a profile photo on the house server (`EVEN_AVATAR_DIR`).
  Server resizes to ≤512px on the long edge and re-encodes JPEG ≤500KB.
  Membership required. Replaces any previous photo.
- `DELETE /v1/me/avatar` → member — clear the caller's photo.
- `GET /v1/members/{id}/avatar` → `image/jpeg` — same-household only.
  `404 no_avatar` when unset. `ETag` from `avatar_updated_at`;
  `Cache-Control: private, max-age=3600`. Supports `If-None-Match`.
- `POST /v1/households` `{name, display_name}` → household (creator =
  `#A6552F` terracotta; opens week 1)
- `POST /v1/households/join` `{invite_code, display_name}` → household
  (joiner = `#37756D` pine; 409 `household_full` on 3rd member)
- `GET  /v1/summary` → `{week, pebbles: [{member_id, weight}...ordered oldest→newest],
  percent_me, percent_partner, caption, sections: [{key:"chore"|"admin", label, tasks:[task]}],
  pending_draft_count}`  // caption per design logic
  `pending_draft_count` counts only the caller's own pending drafts — the
  Inbox badge must not reveal what is sitting in the partner's mail.
- `GET  /v1/ws/household` → WebSocket upgrade (auth + household membership).
  Long-lived household channel. Server → client JSON text frames:

  ```json
  { "type": "household.invalidate", "scopes": ["summary"],
    "reason": "task_toggled", "actor_member_id": "<uuid>" }
  ```

  - `scopes` — which REST resources to refetch (`summary` today; more later).
  - `reason` — `task_created` | `task_updated` | `task_deleted` | `task_toggled`.
  - Clients ignore unknown `type`s. Optional client `{"type":"ping"}` →
    server `{"type":"pong"}` (keepalive); protocol-level WS pings also fine.
  - Emitted after successful task create / patch / delete / toggle. Single-node
    in-process hub (home `evend`); not multi-replica.

- `POST /v1/tasks` `{title, section, owner_member_id, weight, recurrence, due_on?,
  recurrence_until?, recurrence_count?}` — either partner may create, for
  **either** owner (sending work over is allowed)
- `PATCH /v1/tasks/{id}` (same fields, plus `clear_due_on?: true` to remove a
  date and its mapped Calendar event, and `clear_recurrence_end?: true` to make a
  repeat unbounded again) · `DELETE /v1/tasks/{id}` (archives) — **owner only**
- `POST /v1/tasks/{id}/toggle` → task — creates/removes open-week completion —
  **owner only**
- `POST /v1/tasks/{id}/calendar/resolve` `{action:"acknowledge"|"restore"|"retry"}`
  → task — acknowledges an imported Calendar edit, recreates an event removed
  directly in Google Calendar, or retries a failed Calendar write —
  **owner only**

### Task ownership — see everything, change only your own

Both partners read every todo (`/v1/summary` and `/v1/calendar` are
household-wide; the beam only reads honestly when both sides are visible), but
completing, editing, resolving and deleting a todo belong to the member it is
assigned to. `PATCH` / `DELETE` / `toggle` / `calendar/resolve` return `403
not_owner` — *"this todo belongs to your partner — trade it if it should be
yours"* — when `owner_member_id` is not the caller.

- `POST /v1/tasks` is deliberately **not** gated: a member may capture work for
  the other (the Inbox review sheet and the Today composer both offer the owner
  toggle).
- Reassignment is an edit, so it follows the same rule: the **current** owner
  (read from the stored row, never from the request body) is the only one who
  can hand a todo over via `PATCH {owner_member_id}`. A partner cannot claim a
  todo by patching itself in.
- `POST /v1/trades` stays the way work moves across for the coming week; it is
  unaffected by this rule.

### Recurrence — one task row, an unbounded or bounded series

A recurring task is a **rule**, never a set of pre-created rows. `due_on` (or the
capture date when there is none) is the **anchor** the cadence counts from, and
`/v1/summary` returns exactly one entry per rule carrying the state of the
current occurrence. Per-date expansion happens only in `/v1/calendar`, which
suffixes repeat items as `{task_id}:{YYYY-MM-DD}`.

A repeat ends in one of three ways:

| Client picks | Sends | Series ends |
| --- | --- | --- |
| Never | neither field | never — runs until the task is deleted |
| On a date | `recurrence_until` | after that date |
| After N times | `recurrence_count` (≥ 1) | after the Nth scheduled occurrence |

`recurrence_count` records the intent; the server derives `recurrence_until` from
it (`anchor + (count − 1) × interval`) and returns **both**. All occurrence maths
— summary visibility, toggle eligibility, calendar expansion, the Calendar
`RRULE` — reads only `recurrence_until`, so a bounded repeat has a single end
date regardless of how it was expressed. Sending both fields is `400
bad_recurrence_end`; sending either on `recurrence: "none"` is the same error.

Once the last occurrence has passed, the task stops appearing in `/v1/summary`
and `/v1/calendar`. It is not archived automatically — history stays intact and
`GET /v1/tasks/{id}` still resolves it.

`meta_line` describes the **next** occurrence, not the anchor, so a healthy
weekly chore never reads as overdue. Daily and every-2-day repeats omit the date
(it is always today by construction) and a bounded repeat appends its end:

```
TOMORROW · WEEKLY            unbounded weekly, next hit tomorrow
AUG 15 · WEEKLY · UNTIL SEP 12
DAILY · 6 TIMES
VATTENFALL · TODAY           one-off from a Gmail draft
```
- `GET  /v1/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD` → `{from, to, items}` —
  dated todos in the requested window (maximum 120 days)
- `POST /v1/calendar/sync` → `{calendar_id, imported, updated, deleted,
  unchanged, last_synced_at}` — reconciles only the dedicated shared Google
  Calendar; imports direct events, applies external title/date edits, and marks
  remote deletions for review without archiving local todos
- `POST /v1/google/connect` `{code, redirect_uri, code_verifier?}` → google
  status — connects **the calling member's own** Gmail. A second member
  connecting does not replace the first; each has their own mailbox.
- `GET  /v1/google/status` → `{connected, partner_connected,
  email?, last_sync_at?, last_sync_count?, calendar_last_sync_at?,
  sync_running?, scanned?, classified?, created?, has_more?}` — `connected`
  and every counter describe the **caller's** connection.
  `partner_connected` is a bare boolean: the partner's address is never
  disclosed. `calendar_last_sync_at` is the household's shared calendar.
- `POST /v1/google/disconnect` → `{connected: false, partner_connected,
  calendar_owner_transferred, calendar_error?}` — drops only the caller's
  mailbox. Drafts it already produced stay in their inbox; they simply stop
  refreshing. The shared calendar survives.
  **Calendar side effect:** when the caller owns the shared calendar and the
  partner is connected, ownership is transferred **before** the caller's token
  is deleted (the handover needs it) — `calendar_owner_transferred: true`.
  With no other connected member the calendar id is kept and publishing pauses
  until someone reconnects, which adopts it. A non-owner disconnect leaves the
  calendar untouched and best-effort revokes their reader grant. A failed
  handover never blocks the disconnect: it returns `calendar_error` copy for
  the remaining partner.
- `POST /v1/google/sync` → `202 {started: true}` — scans the caller's mailbox.
  409 `not_connected` when the caller has not connected, 409 `sync_running`
  while their own scan is in flight (the partner's scan never blocks it).
- `GET  /v1/google/calendar-info` → `{calendar_id, shared, share_url?, owner,
  listed, can_add}` — the household's shared calendar, readable by either
  member as soon as **one** of them is connected.
  `owner` — the caller's Google account owns the calendar (Google gives a
  secondary calendar exactly one owner; Even stores it as
  `households.calendar_owner_member_id`).
  `listed` — it is already on the caller's Google Calendar list (owners always
  are). `can_add` — the caller has their own Google connected, a shared
  calendar exists, and they are neither owner nor listed: show the one-tap
  confirm.
- `POST /v1/google/calendar/add` → `{calendar_id, listed: true, owner,
  adopted?}` — the partner's one-tap confirm. With the **owner's** token it
  grants the caller `reader` ACL (mirror-only: never writer — edits belong in
  Even), then with the **caller's** token inserts the calendar into their
  Google CalendarList, so `Even — {household}` appears without an email invite.
  409 `not_connected` (caller has no Google), 409 `not_ready` (no shared
  calendar yet), 409 `already_owner`, 409 `reconnect_required` /
  `owner_reconnect_required` when a stored grant predates the Calendar scope
  bump, 502 `calendar_failed` when Google refuses. When the recorded owner has
  no connection left, the caller adopts the calendar instead (a fresh calendar
  under their account, open dated todos re-published) → `owner: true,
  adopted: true`.
- `GET  /v1/drafts?status=pending` → `[draft]` — **only the caller's own**
  drafts: those from their Gmail, plus the ones they created by hand.
- `POST /v1/drafts` `{from_label, subject, summary?, urgency, title?, owner_member_id?,
  amount_cents?, due_on?, reminder?}` (title defaults to subject). The draft's
  source is the caller; `owner_member_id` still assigns the resulting todo to
  either member.
- `PATCH /v1/drafts/{id}` `{title?, owner_member_id?, amount_cents?, due_on?, reminder?,
  reply_text?, reply_status?}` — reply text remains editable; the app opens a
  Gmail compose draft and never sends email through the API.
- `POST /v1/drafts/{id}/approve` → `{draft, task}` — tx: draft approved +
  admin task (weight 2, owner/due from draft, meta from label+due)
- `POST /v1/drafts/{id}/dismiss` → draft
- Every `/v1/drafts/{id}` route is scoped to the caller's own inbox: a
  partner's draft is `404 not_found`, never 403 — its existence is not theirs
  to learn.
- `GET  /v1/money` → `{balance_cents, debtor_member_id?, creditor_member_id?,
  feed: [{kind:"expense"|"settlement", ...expense|settlement}]}` — balance ≥ 0;
  null members when even. feed newest-first, current cycle + last settlement.
- `POST /v1/expenses` `{title, amount_cents, paid_by_member_id, incurred_on}`
- `POST /v1/settle` → money — tx: settlement for current balance, marks
  expenses settled; 409 `already_even` when balance 0.
- `GET  /v1/reset` → `{week, rows: [{key:"chores"|"admin"|"money", label,
  me_pct, partner_pct}], biggest_carry, appreciations: [appreciation],
  trades: [trade]}` — biggest_carry = computed sentence.
- `PUT  /v1/appreciations/mine` `{body?, said}` → appreciation (mine = from me
  to partner, open week; upsert)
- `POST /v1/trades` `{task_id}` → trade — hands MY task to partner (or theirs
  to me), open week
- `POST /v1/trades/{id}/accept` `{accepted: bool}` → trade — only the
  receiving side accepts
- `DELETE /v1/trades/{id}`
- `POST /v1/week/close` → `{closed_week, new_week}` — tx: apply accepted
  trades (swap task owners), delete one-off done tasks, keep recurring
  (completions archived with the closed week), open next week.

## Semantics
- Percentages: `round(100 * my_weight / total)`; 50/50 when no completions.
- Caption: empty → "Empty pans. A new week, level by definition"; |Δ|≤1 →
  "Level. Enjoy it while it lasts"; ≤4 → "Close to even. Not a competition —
  but noted"; else "Leaning <name> — mostly the admin and the remembering"
- All queries household-scoped by the authenticated member; cross-household
  access is 404, never 403. Inside a household, 403 means the resource exists
  and is visible but is not the caller's to change (`not_owner` on tasks).
- **The inbox is per member; Today and the Calendar are shared.** Each member
  connects their own Gmail, and every draft carries the member whose mailbox
  (or hand) produced it. Drafts, the Inbox badge, sync jobs, and the
  already-scanned ledger are all filtered by that member — a partner sees
  their own not-connected state and their own mail, never yours. Approval is
  where the two worlds meet: the todo it creates lands on Today and may be
  assigned to either member.
- Solo household (partner not joined): percent_partner = 0, money endpoints
  usable, trades/appreciations 409 `no_partner`.
- Google Calendar is read only through the dedicated household calendar, never
  from a member's primary calendar. That calendar belongs to the **household**,
  not to whoever connected first: it is created once, kept on the household
  record, and written with whichever member's token is available — so it keeps
  working when only one partner has connected, and survives them disconnecting. A direct Calendar deletion is represented
  as `external_deleted` until the household restores its local todo to Calendar
  or archives it. Calendar title/date edits are copied into the todo and remain
  `external_changed` until acknowledged.
- Daily and every-two-day todos record a completion for each scheduled date.
  `due_on` is their optional first occurrence; without it, the capture date is
  the anchor. Dated recurring todos publish one Google Calendar RRULE.
- On a phone that enables Even notifications, the app mirrors upcoming dated
  Calendar occurrences as local 09:00 on-the-day alerts. These alerts are
  device-local, refreshed from `GET /v1/calendar`, and do not replace Google
  Calendar's shared reminders.
