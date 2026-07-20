-- Calendar synchronization state is stored on each todo so external Google
-- edits are visible and recoverable instead of silently being overwritten.
alter table tasks add column calendar_sync_state text not null default 'not_scheduled'
  check (calendar_sync_state in ('not_scheduled', 'synced', 'external_changed', 'external_deleted', 'retry_required'));
alter table tasks add column calendar_last_synced_at timestamptz;
alter table tasks add column calendar_last_error text;

update tasks
set calendar_sync_state = 'synced'
where google_event_id is not null;

-- Calendar event ids are unique within one household. This makes repeated
-- imports of a direct Google Calendar event idempotent.
create unique index tasks_household_google_event_idx
  on tasks(household_id, google_event_id) where google_event_id is not null;

alter table google_accounts add column calendar_last_sync_at timestamptz;
