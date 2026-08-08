-- Per-member Gmail. Each member connects their OWN mailbox and sees only the
-- drafts it produced; the Google Calendar stays the one shared surface, so it
-- moves off google_accounts onto the household itself.

-- 1. google_accounts becomes one row per member (was one per household).
alter table google_accounts add column member_id uuid references members(id) on delete cascade;

update google_accounts g
set member_id = coalesce(
    g.connected_by,
    (select m.id from members m where m.household_id = g.household_id
     order by m.created_at, m.id limit 1));

-- A row whose household lost every member can never be attributed; it is dead
-- weight (its token is unusable without a caller) so it goes.
delete from google_accounts where member_id is null;

alter table google_accounts alter column member_id set not null;
alter table google_accounts drop constraint google_accounts_household_id_key;
alter table google_accounts add constraint google_accounts_member_id_key unique (member_id);
create index if not exists google_accounts_household_idx on google_accounts(household_id);

-- 2. drafts carry the mailbox they came from. created_by is the source member
-- for both origins: the poller stamps it with the syncing member, and a manual
-- draft is stamped with its creator. owner_member_id is the *assignee* and can
-- be handed to the partner on the review sheet, so it must not be used here.
alter table drafts add column source_member_id uuid references members(id);
update drafts set source_member_id = created_by where source_member_id is null;
alter table drafts alter column source_member_id set not null;
create index if not exists drafts_source_member_status_idx
  on drafts(household_id, source_member_id, status);

-- A Gmail message is unique per mailbox, not per household: both partners may
-- receive the same message and each deserves their own draft.
drop index if exists drafts_gmail_msg_idx;
create unique index drafts_gmail_msg_idx
  on drafts(household_id, source_member_id, gmail_message_id)
  where gmail_message_id is not null;

-- 3. processed_emails verdicts are per mailbox too, or one member's scan would
-- teach the other's poller to skip mail it has never seen.
alter table processed_emails add column member_id uuid references members(id) on delete cascade;

update processed_emails p
set member_id = coalesce(
    (select g.member_id from google_accounts g where g.household_id = p.household_id
     order by g.connected_at limit 1),
    (select m.id from members m where m.household_id = p.household_id
     order by m.created_at, m.id limit 1));

delete from processed_emails where member_id is null;

alter table processed_emails alter column member_id set not null;
alter table processed_emails drop constraint processed_emails_pkey;
alter table processed_emails add primary key (household_id, member_id, gmail_message_id);

-- 4. The shared calendar belongs to the household, not to whoever connected
-- first — it must survive that member disconnecting. The google_accounts
-- columns stay in place (vestigial) until 013 confirms production is happy.
alter table households add column calendar_id text not null default 'primary';
alter table households add column calendar_last_sync_at timestamptz;

update households h
set calendar_id = g.calendar_id,
    calendar_last_sync_at = g.calendar_last_sync_at
from google_accounts g
where g.household_id = h.id and g.calendar_id is not null and g.calendar_id <> 'primary';
