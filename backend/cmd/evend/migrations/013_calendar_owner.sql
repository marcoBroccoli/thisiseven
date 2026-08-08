-- The shared "Even — {household}" calendar is a Google *secondary* calendar,
-- and Google gives every secondary calendar exactly one owning account. Even
-- has to know which member that is: only their token may grant the partner
-- reader access, and when they disconnect Google the ownership has to move to
-- the other partner before their refresh token is dropped.

alter table households
  add column calendar_owner_member_id uuid references members(id) on delete set null;

-- Backfill: a household that already has a real (non-primary) calendar got it
-- from whoever connected Google first — the lazy create ran with that member's
-- token. Households with no calendar stay NULL; ownership is established the
-- next time the calendar is created.
update households h
set calendar_owner_member_id = (
    select g.member_id from google_accounts g
    where g.household_id = h.id
    order by g.connected_at, g.member_id
    limit 1)
where h.calendar_id is not null and h.calendar_id <> 'primary';

-- Whether a member has the household calendar on their own Google CalendarList.
-- Server-tracked (set when the "add to my Google" confirm succeeds) rather than
-- asked of Google on every status read: the list call is an extra round trip on
-- a screen that must render instantly, and it is the same fact.
alter table google_accounts add column calendar_listed_at timestamptz;

-- The owner always sees their own calendar; record that so a transfer or a
-- reconnect does not ask them to "add" a calendar they own.
update google_accounts g
set calendar_listed_at = now()
from households h
where h.id = g.household_id and h.calendar_owner_member_id = g.member_id;
