-- Gmail discovery + Google Calendar (household-level connection).

create table google_accounts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null unique references households(id) on delete cascade,
  email text not null,
  refresh_token text not null,
  connected_by uuid references members(id),
  calendar_id text not null default 'primary',
  connected_at timestamptz not null default now(),
  last_sync_at timestamptz,
  last_sync_count int not null default 0
);

alter table drafts add column gmail_message_id text;
alter table drafts add column source_from text;
alter table drafts add column source_preview text;
-- One draft per Gmail message per household, ever — dismissed/approved
-- drafts keep their id so a message is never resurrected on resync.
create unique index drafts_gmail_msg_idx
  on drafts(household_id, gmail_message_id) where gmail_message_id is not null;

alter table tasks add column google_event_id text;
alter table tasks add column google_event_url text;
