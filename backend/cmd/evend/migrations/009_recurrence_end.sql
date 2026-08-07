-- A repeat used to run forever, which left "weekly" with no answer to "until
-- when?". A series can now end on a date or after a number of occurrences.
--
-- recurrence_count records what the household picked; recurrence_until is the
-- derived last-occurrence date and the only column occurrence maths reads, so a
-- bounded series has one end date however it was expressed.
alter table tasks
  add column recurrence_until date,
  add column recurrence_count int;

alter table tasks
  add constraint tasks_recurrence_count_positive
    check (recurrence_count is null or recurrence_count >= 1),
  add constraint tasks_recurrence_end_needs_repeat
    check (
      recurrence <> 'none'
      or (recurrence_until is null and recurrence_count is null)
    );

-- Summary and calendar queries filter live series by this date on every read.
create index tasks_recurrence_until_idx on tasks(recurrence_until)
  where recurrence <> 'none' and archived_at is null;
