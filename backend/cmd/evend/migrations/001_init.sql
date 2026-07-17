create extension if not exists pgcrypto;

create table households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

create table members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  user_id uuid not null unique,
  display_name text not null,
  color text not null check (color in ('clay','teal')),
  created_at timestamptz not null default now(),
  unique (household_id, color)
);

create table weeks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  week_index int not null,
  started_on date not null,
  closed_at timestamptz,
  unique (household_id, week_index)
);
-- Exactly one open week per household.
create unique index weeks_open_one on weeks(household_id) where closed_at is null;

create table tasks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  title text not null,
  section text not null check (section in ('chore','admin')),
  owner_member_id uuid not null references members(id),
  weight int not null check (weight between 1 and 3),
  recurrence text not null default 'none'
    check (recurrence in ('none','daily','every_2_days','weekly')),
  due_on date,
  origin_label text,           -- set when born from an approved draft
  archived_at timestamptz,
  created_by uuid references members(id),
  created_at timestamptz not null default now()
);
create index tasks_household_open_idx on tasks(household_id) where archived_at is null;

create table completions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id) on delete cascade,
  week_id uuid not null references weeks(id) on delete cascade,
  member_id uuid not null references members(id),
  weight int not null,
  completed_at timestamptz not null default now(),
  unique (task_id, week_id)
);
create index completions_week_idx on completions(week_id);

create table drafts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  from_label text not null,
  subject text not null,
  summary text,
  urgency int not null default 1 check (urgency between 1 and 3),
  title text not null,
  owner_member_id uuid not null references members(id),
  amount_cents bigint check (amount_cents > 0),
  due_on date,
  reminder text not null default '3_days'
    check (reminder in ('on_day','1_day','3_days','1_week')),
  status text not null default 'pending'
    check (status in ('pending','approved','dismissed')),
  created_by uuid not null references members(id),
  resulting_task_id uuid references tasks(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
create index drafts_household_status_idx on drafts(household_id, status);

create table settlements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  from_member_id uuid not null references members(id),
  to_member_id uuid not null references members(id),
  amount_cents bigint not null,
  created_at timestamptz not null default now()
);

create table expenses (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  title text not null,
  amount_cents bigint not null check (amount_cents > 0),
  paid_by_member_id uuid not null references members(id),
  incurred_on date not null,
  settlement_id uuid references settlements(id),
  created_at timestamptz not null default now()
);
create index expenses_household_unsettled_idx on expenses(household_id)
  where settlement_id is null;

create table appreciations (
  id uuid primary key default gen_random_uuid(),
  week_id uuid not null references weeks(id) on delete cascade,
  from_member_id uuid not null references members(id),
  to_member_id uuid not null references members(id),
  body text,
  said boolean not null default false,
  created_at timestamptz not null default now(),
  unique (week_id, from_member_id)
);

create table trades (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  week_id uuid not null references weeks(id) on delete cascade,
  task_id uuid not null references tasks(id) on delete cascade,
  from_member_id uuid not null references members(id),
  to_member_id uuid not null references members(id),
  proposed_by uuid not null references members(id),
  accepted boolean not null default false,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  unique (week_id, task_id)
);
