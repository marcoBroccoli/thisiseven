-- Every scanned Gmail message gets a verdict record so non-actionable mail is
-- never re-fetched or re-classified, and "read more" pagination knows what is
-- left. Drafts remain only for actionable mail.
create table if not exists processed_emails (
    household_id     uuid not null references households(id) on delete cascade,
    gmail_message_id text not null,
    actionable       boolean not null,
    processed_at     timestamptz not null default now(),
    primary key (household_id, gmail_message_id)
);

-- Backfill: anything already turned into a draft counts as processed.
insert into processed_emails (household_id, gmail_message_id, actionable, processed_at)
select household_id, gmail_message_id, true, coalesce(created_at, now())
from drafts
where gmail_message_id is not null
on conflict do nothing;
