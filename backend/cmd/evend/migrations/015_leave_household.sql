-- Leaving a household. A departure is a *soft* delete: the member row stays,
-- because the history that references it does — completions on the closed
-- weeks, the expenses they paid, the settlements and trades between the two of
-- them. Deleting the row would either destroy that history or leave dangling
-- references (every one of those foreign keys is NO ACTION on purpose).
--
-- A row with left_at set is invisible everywhere a household's *current* people
-- are listed: membership resolution, the member list, member_count, the
-- two-person cap. The seat is free again.
--
-- And it is revivable: unique (user_id, household_id) forbids a second row, so
-- a partner who comes back takes this same row (left_at cleared, name and
-- colour rewritten) rather than inserting a duplicate.

alter table members add column left_at timestamptz;

-- Every "who lives here now" query filters on this; the partial index keeps
-- the household lookups cheap.
create index if not exists members_active_idx
  on members (household_id) where left_at is null;
