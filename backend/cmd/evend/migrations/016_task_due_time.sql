-- A todo may now say *when* on its due day. Null is the whole history and the
-- default: no time means the same all-day event Even has always written, so
-- nothing about an existing todo changes.
--
-- It is a wall-clock time on the household's day (Europe/Amsterdam), not an
-- instant — 09:30 stays 09:30 across a DST boundary, exactly like due_on stays
-- the same civil date. `time` (no zone) is the honest column for that.
alter table tasks add column due_time time;

-- A time without a day is not a schedule. Clearing the date clears the time
-- with it (the API does this); the constraint keeps that true for every writer.
alter table tasks
  add constraint tasks_due_time_needs_due_on
    check (due_time is null or due_on is not null);
