-- Daily and every-two-day chores need one completion per occurrence rather
-- than one checkbox for the whole week. Weekly and one-off tasks retain the
-- existing completions table and its week-based ritual.
create table recurring_completions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id) on delete cascade,
  occurrence_on date not null,
  member_id uuid not null references members(id),
  weight int not null check (weight between 1 and 3),
  completed_at timestamptz not null default now(),
  unique (task_id, occurrence_on)
);
create index recurring_completions_date_idx on recurring_completions(occurrence_on);

-- Preserve any completions created before occurrence tracking existed. The
-- completion timestamp is the only defensible historical occurrence date.
insert into recurring_completions (task_id, occurrence_on, member_id, weight, completed_at)
select c.task_id, c.completed_at::date, c.member_id, c.weight, c.completed_at
from completions c
join tasks t on t.id = c.task_id
where t.recurrence in ('daily', 'every_2_days')
on conflict (task_id, occurrence_on) do nothing;

delete from completions c
using tasks t
where t.id = c.task_id and t.recurrence in ('daily', 'every_2_days');
