-- Multi-household. A household still holds at most TWO members — the fairness
-- model assumes a pair — but a *person* may now belong to several households
-- (their own place, a partner's, a shared flat). One member row per (user,
-- household); everything downstream (tasks, drafts, google_accounts) is already
-- keyed by member_id, so a user gets a clean per-household identity for free.

alter table members drop constraint if exists members_user_id_key;
create unique index if not exists members_user_household_key
  on members (user_id, household_id);

-- Email invites without SMTP: the owner records their partner's address, and
-- the invite surfaces the next time a user whose auth email matches signs in
-- (GET /v1/households). No mail is ever sent from evend. The invite_code flow
-- stays exactly as it was — this is the second door, not a replacement.
create table household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  email text not null,                                  -- stored lowercased
  invited_by_member_id uuid not null references members(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','declined','revoked')),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

-- A two-person household has at most one empty seat, so at most one live
-- invite. Resolved invites (accepted/declined/revoked) stay as history.
create unique index household_invites_one_pending
  on household_invites (household_id) where status = 'pending';

-- The lookup that runs on every household list: "is anyone waiting for me?".
create index household_invites_email_idx on household_invites (email);
