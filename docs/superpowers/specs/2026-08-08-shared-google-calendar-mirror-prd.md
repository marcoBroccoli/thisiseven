# PRD — Shared Google Calendar (mirror) for both partners

**Status:** product decision locked; **do not implement in this thread** (needs live Google OAuth creds + two real accounts to verify).  
**Audience:** implementing agent / engineer.  
**Date:** 2026-08-08  
**Related:** `docs/product/API.md` (Calendar + Google), `backend/internal/api/google.go`, `backend/internal/google/google.go`, `Sources/Core/EvenCore/GoogleConnect.swift`

---

## One-liner

Both household members should see the same **Even household calendar** in their **Google Calendar apps**, as a **read-only mirror** of dated todos. Even remains the only place that creates/edits/deletes the underlying task model; Google is a viewing surface. Adding the calendar to the second person’s Google is a **one-tap confirm** in Connections — not a manual “paste calendar id” chore. If the Google account that **owns** the secondary calendar disconnects, **ownership moves to the other connected partner**.

---

## Problem

Even already creates a secondary Google calendar (`Even — {household}`) and writes dated todos into it. That calendar lives on **whichever member connected first**. The partner does **not** automatically see it in Google Calendar. There is a `GET /v1/google/calendar-info` + `share_url`, but no productized “add to my Google” path and **no ACL / CalendarList wiring**.

Without this, “shared calendar” is true inside Even, but false in the place couples already look (Google Calendar).

---

## Goals

1. After both partners connect Google, each can have `Even — {household}` visible in the Google Calendar UI (web + iOS Google Calendar).
2. That calendar is a **mirror**: partners do **not** get writer ACL. Edits belong in Even.
3. Second member opts in with one Connections confirm (not automatic, not a raw calendar-id paste).
4. If the calendar **owner** disconnects Google, ownership **transfers** to the remaining connected partner so Even can keep publishing events.
5. Contract stays aligned with API.md: never read/write a member’s **primary** calendar; only the dedicated household calendar.

## Non-goals (this PRD)

- Two-way edit from Google (title/date drag as a first-class authoring path). Existing `POST /v1/calendar/sync` + `external_changed` / `external_deleted` may remain for **defense** if someone with residual access edits Google, but the product promise is mirror-only.
- Sharing to anyone outside the two-person household.
- Writing to either member’s primary calendar.
- Full recreate of event history for aesthetics (colors, notifications preferences) beyond what Even already publishes.
- Implementing or verifying against Google in the agent session that authored this PRD.

---

## Product decisions (locked)

| Decision | Choice |
| --- | --- |
| Edit model | **Mirror only** — Even authoritative; Google read-only for the non-owner (and prefer not inviting partner edits) |
| How it appears for partner | **One confirm** in Connections: “Add Even calendar to my Google” |
| Owner disconnects | **Ownership transfers** to the other connected partner |
| Solo / one connected | Calendar may exist under the only connected member; partner confirm appears only when they connect and a household calendar id exists |

---

## Current system (what to build on)

Already in repo:

- Lazy `ensureHouseholdCalendar` → `POST /calendar/v3/calendars` → `households.calendar_id`.
- Event insert/update/delete + `POST /v1/calendar/sync` against that id only.
- Token pick: `householdCalendarAccount` (caller’s token, else any household token).
- `GET /v1/google/calendar-info` → `{calendar_id, shared, share_url?}`.
- OAuth scopes today (iOS + server AuthURL):  
  `gmail.readonly` + **`calendar.events`** + `openid email profile`.

Gaps:

- No `acl.insert` / `acl.delete` helpers.
- No `calendarList.insert` for the partner.
- No stored **calendar owner member id** (only `calendar_id`).
- Disconnect does not transfer ownership.
- Scope `calendar.events` is likely **insufficient** for calendar create + ACL + CalendarList; expect bump to  
  `https://www.googleapis.com/auth/calendar` (keep gmail.readonly). Re-consent required for existing users.

---

## Approaches considered

### A — Owner ACL (reader) + partner CalendarList insert *(recommended)*

1. Keep creating the secondary calendar under the first member who needs a write (today’s lazy create), and **persist `calendar_owner_member_id`** on `households`.
2. When partner taps confirm:
   - With **owner** access token: `acl.insert` for partner email, role **`reader`**.
   - With **partner** access token: `calendarList.insert` for that `calendar_id` (so it appears in their list without hunting an email invite).
3. On **owner disconnect**:
   - If partner still has a Google connection: transfer ownership (see Transfer below), update `calendar_owner_member_id`, ensure Even can still write with the new owner’s token.
   - If nobody else is connected: keep `calendar_id` on the household row but publishing pauses until someone reconnects (then that member becomes owner / recreate path — specify in plan).

**Pros:** Matches Google’s real sharing model; both see the same calendar id; Even keeps one source of event ids.  
**Cons:** Needs broader OAuth scope; ACL + List APIs must be tested with two accounts; disconnect transfer is non-trivial.

### B — Soft `share_url` only (status quo polish)

Surface `calendar-info.share_url` in Connections and tell the partner to open it.

**Pros:** Tiny change.  
**Cons:** Fails the product goal (“they will see a new one”); flaky UX; no ownership transfer story.

### C — Dual calendars (one secondary per member, Even fans out writes)

Create `Even — …` under each connected account and insert the same logical events twice.

**Pros:** No ACL.  
**Cons:** Diverges event ids, sync, deletes, and “one shared calendar”; fights API.md. **Reject.**

**Recommendation:** **Approach A.**

---

## Ownership transfer (required behavior)

Google secondary calendars are owned by one account. When that member disconnects:

**Intent:** the other partner becomes the owner Even uses for all future writes, and their Google Calendar continues to show the household calendar.

**Preferred mechanism (implementing agent should spike both and pick what Google allows with our OAuth client):**

1. **ACL promote + demote (ideal if Google allows):**  
   While owner token still works (run **before** deleting `google_accounts` row):  
   - `acl.insert` / patch partner to role **`owner`** (or writer if owner role is blocked).  
   - Remove or downgrade old owner as needed.  
   - Set `households.calendar_owner_member_id` to partner.  
   - Then delete disconnecting member’s `google_accounts` row.

2. **Recreate + migrate (fallback):**  
   - Create new secondary calendar under the remaining member.  
   - Re-publish open dated todos (Even already knows how to insert events); update `tasks.google_event_id` / urls.  
   - Point `households.calendar_id` at the new id; old calendar abandoned (optional best-effort delete with dying token).  
   - Partner already “has” their own calendar; confirm UI may no-op if they are the new owner.

**Hard rule:** do transfer work **while the disconnecting owner’s refresh token is still available**. Order matters: transfer → then delete tokens.

If transfer fails, disconnect should still succeed for mailbox privacy, but status should expose a clear calendar error for the remaining partner (toast / Connections copy) so they can retry “Repair shared calendar” later — exact copy left to Connections design.

---

## User-facing flow

### First connected member

1. Connects Google (existing Connections flow).
2. First dated-todo publish (or optional eager ensure on connect — prefer **keep lazy create** unless transfer/testing needs eager) creates `Even — {name}` on their account.
3. They already see it in Google (owner). No confirm needed.

### Second member

1. Connects Google.
2. Connections (setup or settings) shows primary CTA when household has a non-primary `calendar_id` and caller is **not** already subscribed / not owner:  
   **“Add Even calendar to my Google”**.
3. Tap → API performs ACL reader + CalendarList insert → success state: “On your Google Calendar”.
4. Failure → toast with retry; do not claim success.

### Disconnect

1. If caller is **not** calendar owner → existing disconnect (mailbox only); ACL entry for them may be removed best-effort.
2. If caller **is** calendar owner and partner connected → **transfer ownership**, then drop caller’s Google account.
3. If caller is owner and partner **not** connected → keep `calendar_id`; publishing waits for a reconnect; on partner (or same user) reconnect, establish ownership again.

---

## API / data contract (proposed — update `docs/product/API.md` when implementing)

### Schema

On `households` (names indicative):

- `calendar_id` — existing
- `calendar_owner_member_id` — nullable uuid/text FK to members; set on create; updated on transfer

Optional: `calendar_subscribed_member_ids` **not** required if status is derived via Google CalendarList get; prefer **server-tracked** `google_accounts.calendar_listed_at` or a small join table if Google list calls are flaky — implementing agent chooses the simpler reliable check.

### Endpoints

Extend or add (keep router ↔ API.md in sync):

- `GET /v1/google/calendar-info`  
  Enrich with something like:  
  `{ calendar_id, shared, share_url?, owner: bool, listed: bool, can_add: bool }`  
  - `owner` — caller is `calendar_owner_member_id`  
  - `listed` — already on caller’s CalendarList (or owner)  
  - `can_add` — connected + household calendar ready + not owner + not listed  

- `POST /v1/google/calendar/add` (name flexible)  
  - Auth: household member with own Google connected  
  - 409 if no household calendar yet (`not_ready`)  
  - 409 if caller is owner (`already_owner`)  
  - Performs ACL reader + CalendarList insert  
  - 200 `{ calendar_id, listed: true }`  

- `POST /v1/google/disconnect`  
  - Side effect: ownership transfer when applicable (document in API.md)  
  - Response may include `calendar_owner_transferred: bool` / `calendar_error?` for client copy  

Do **not** return the partner’s email to the non-owner beyond what connect already exposes for self.

### Scopes

Bump Calendar scope to full calendar scope for create/ACL/list. Both:

- `Sources/Core/EvenCore/GoogleConnect.swift`
- `backend/internal/google/google.go` `AuthURL` (and any docs/scripts)

Existing connections must re-consent before ACL/add works.

---

## Backend work (implementation checklist for the other agent)

1. Google client helpers: `InsertACL`, `DeleteACL` (optional), `InsertCalendarList`, maybe `GetCalendarListEntry`, optional `PatchACL` for owner promote.
2. Persist `calendar_owner_member_id` in migration; set in `ensureHouseholdCalendar`.
3. `POST …/calendar/add` as above.
4. Hook transfer into disconnect (token still present).
5. Widen OAuth scopes; document re-consent.
6. Tests with fake Google HTTP (pattern in `calendar_test.go`): create → add (ACL + list) → disconnect owner transfers.
7. Update `docs/product/API.md` + short note in `backend/README.md`.

## iOS work

1. Connections (setup + settings/profile manage mode): state from `calendar-info` (`can_add` / `listed`).
2. Confirm button → `calendar/add` → success / error toast.
3. No new Google SDK surface beyond existing OAuth; re-consent when scope string changes.
4. Previews + Connections tests for the new footer/row states.
5. Do **not** use IGTabBar for this control; keep Connections chrome patterns.

## Sync / chaos policy (why mirror)

Even already has two-way reconcile for the dedicated calendar. This PRD **narrows the product promise**: we do not grant the partner **writer** ACL, so day-to-day Google edits from the partner should not happen. Owner may still edit in Google if they use the Google UI; existing sync states remain a safety net, not the happy path. Happy path: change due dates / titles in Even → publish/update event.

---

## Success criteria

- [ ] Two real Google accounts in one household: after second taps confirm, both see `Even — …` in Google Calendar with the same events Even published.
- [ ] Partner cannot edit events in Google (reader); attempting to change in Google UI is blocked or non-persistent for them.
- [ ] Owner disconnect with partner still connected: new writes from Even still land on a calendar the partner sees; `calendar_owner_member_id` updated.
- [ ] No writes to `primary`.
- [ ] API.md and router match; Go unit tests cover ACL/add/transfer against the fake Google server.
- [ ] Re-consent path works after scope bump.

## Test plan (needs real creds — not this agent)

1. Member A connect → approve dated draft → confirm secondary calendar + event on A’s Google.
2. Member B connect → Connections shows Add → success → calendar visible for B.
3. Edit task due date in Even → both Google views update after publish/sync.
4. A disconnect → B still sees calendar; new dated todo from Even still appears for B.
5. B disconnect / A reconnect edge cases per transfer rules.
6. Revoke Calendar scope mid-flight → clear error, no silent success.

---

## Open points for the implementing agent (spike, don’t block the PRD)

1. Whether Google grants **`owner`** ACL via API with our OAuth client, or only writer + recreate fallback.
2. Whether `calendarList.insert` alone is enough after ACL, or the partner must accept a sharing email (prefer API-only; document if Google forces an accept).
3. Eager calendar create on first Google connect vs keep lazy-on-first-event (lazy is fine if Add is hidden until `calendar_id` exists; optionally ensure-on-connect so Add is available immediately).

---

## Out of scope reminders

- No implementation in the session that only produced this PRD.
- No TestFlight / production Google Cloud verification without Umur’s environment.
- Do not expand Inbox/Today calendar UI beyond what’s needed to surface the Add confirm in Connections.
