create extension if not exists pgcrypto;

create type draft_status as enum (
  'pending_approval',
  'approved',
  'rejected',
  'calendar_retry_required',
  'changed_externally'
);

create table households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  shared_calendar_id text,
  created_at timestamptz not null default now()
);

create table household_members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  email text not null,
  role text not null default 'member',
  created_at timestamptz not null default now(),
  unique (household_id, email)
);

create table household_areas (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  name text not null,
  default_owner_id uuid references household_members(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (household_id, name)
);

create table inbox_drafts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  gmail_message_id text not null,
  gmail_label text not null default 'HouseholdTodo',
  source_subject text not null,
  source_from text not null,
  source_received_at timestamptz,
  source_preview text,
  title text not null,
  due_at timestamptz,
  amount numeric(12, 2),
  owner_id uuid references household_members(id) on delete set null,
  area_id uuid references household_areas(id) on delete set null,
  extraction_confidence numeric(4, 3) not null default 0,
  extraction_evidence jsonb not null default '[]'::jsonb,
  status draft_status not null default 'pending_approval',
  approver_id uuid references household_members(id) on delete set null,
  google_event_id text,
  google_event_url text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, gmail_message_id)
);

create table approval_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  draft_id uuid not null references inbox_drafts(id) on delete cascade,
  actor_member_id uuid references household_members(id) on delete set null,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table google_object_mappings (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  draft_id uuid not null references inbox_drafts(id) on delete cascade,
  object_type text not null,
  google_id text not null,
  google_url text,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  unique (object_type, google_id)
);

create index inbox_drafts_household_status_idx on inbox_drafts(household_id, status);
create index inbox_drafts_due_at_idx on inbox_drafts(due_at);
create index approval_events_draft_idx on approval_events(draft_id, created_at desc);

alter table households enable row level security;
alter table household_members enable row level security;
alter table household_areas enable row level security;
alter table inbox_drafts enable row level security;
alter table approval_events enable row level security;
alter table google_object_mappings enable row level security;

create policy "members can read households"
  on households for select
  using (
    exists (
      select 1 from household_members
      where household_members.household_id = households.id
        and household_members.user_id = auth.uid()
    )
  );

create policy "members can read drafts"
  on inbox_drafts for select
  using (
    exists (
      select 1 from household_members
      where household_members.household_id = inbox_drafts.household_id
        and household_members.user_id = auth.uid()
    )
  );

create policy "members can update drafts"
  on inbox_drafts for update
  using (
    exists (
      select 1 from household_members
      where household_members.household_id = inbox_drafts.household_id
        and household_members.user_id = auth.uid()
    )
  );
