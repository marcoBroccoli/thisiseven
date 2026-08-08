-- Fixture data for the even_test database ONLY.
--
-- It exists so the console can be run and screenshotted against something that
-- looks like a real household without ever pointing the service at the live
-- `even` database. Every id is a fixed literal in the ffff… range so re-running
-- this file replaces its own rows and touches nothing else.
--
--   docker exec -i evend-db-1 psql -U even -d even_test -v ON_ERROR_STOP=1 \
--     < admin/server/testdata/seed_even_test.sql
--
-- NEVER run this against `even`.

do $$
begin
  if current_database() <> 'even_test' then
    raise exception 'refusing to seed %, this file is for even_test only', current_database();
  end if;
end $$;

begin;

-- Clean up a previous run (children first; most FKs are NO ACTION on purpose).
delete from recurring_completions where task_id in
  (select id from tasks where household_id in
    ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002'));
delete from completions where task_id in
  (select id from tasks where household_id in
    ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002'));
delete from appreciations where week_id in
  (select id from weeks where household_id in
    ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002'));
delete from trades where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from expenses where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from settlements where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from drafts where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from processed_emails where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from tasks where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from weeks where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from google_accounts where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from household_invites where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from members where household_id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from households where id in
  ('ffff0000-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002');
delete from auth.users where id in
  ('ffff1111-0000-0000-0000-000000000001','ffff1111-0000-0000-0000-000000000002',
   'ffff1111-0000-0000-0000-000000000003','ffff1111-0000-0000-0000-000000000004');

-- GoTrue identities. Spread over the trend window so the dashboard chart has
-- shape. auth.users.confirmed_at is a GENERATED column in this GoTrue version —
-- it is derived from email_confirmed_at and must not be written directly.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at,
                        email_confirmed_at, last_sign_in_at, raw_app_meta_data)
values
 ('ffff1111-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'mara@example.test',  now() - interval '13 days', now(),
  now() - interval '13 days', now() - interval '3 hours', '{"provider":"apple","providers":["apple"]}'),
 ('ffff1111-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'joris@example.test', now() - interval '12 days', now(),
  now() - interval '12 days', now() - interval '1 day', '{"provider":"apple","providers":["apple"]}'),
 ('ffff1111-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'sofie@example.test', now() - interval '6 days',  now(),
  now() - interval '6 days', now() - interval '2 days', '{"provider":"email","providers":["email"]}'),
 -- Signed up, never confirmed, never onboarded: the "stalled onboarding" row
 -- the users page exists to surface.
 ('ffff1111-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'wout@example.test',  now() - interval '2 days',  now(), null, null,
  '{"provider":"email","providers":["email"]}');

insert into households (id, name, invite_code, created_at, calendar_id,
                        calendar_last_sync_at, calendar_owner_member_id)
values
 ('ffff0000-0000-0000-0000-000000000001','Sarphatipark','MARJOR', now() - interval '13 days',
  'even-sarphatipark@group.calendar.google.com', now() - interval '40 minutes', null),
 ('ffff0000-0000-0000-0000-000000000002','De Pijp studio','SOFWTX', now() - interval '6 days',
  'primary', null, null);

insert into members (id, household_id, user_id, display_name, color, created_at, left_at, avatar_path)
values
 ('ffff2222-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000001',
  'ffff1111-0000-0000-0000-000000000001','Mara','#A6552F', now() - interval '13 days', null, '/var/even/avatars/x.jpg'),
 ('ffff2222-0000-0000-0000-000000000002','ffff0000-0000-0000-0000-000000000001',
  'ffff1111-0000-0000-0000-000000000002','Joris','#37756D', now() - interval '12 days', null, null),
 -- A departed seat: the row survives because the history referencing it does.
 ('ffff2222-0000-0000-0000-000000000003','ffff0000-0000-0000-0000-000000000002',
  'ffff1111-0000-0000-0000-000000000003','Sofie','#3B5BDB', now() - interval '6 days', null, null),
 ('ffff2222-0000-0000-0000-000000000004','ffff0000-0000-0000-0000-000000000002',
  'ffff1111-0000-0000-0000-000000000001','Mara','#A6552F', now() - interval '5 days',
  now() - interval '1 day', null);

update households set calendar_owner_member_id = 'ffff2222-0000-0000-0000-000000000001'
 where id = 'ffff0000-0000-0000-0000-000000000001';

insert into weeks (id, household_id, week_index, started_on, closed_at) values
 ('ffff3333-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000001',1,
  current_date - 14, now() - interval '7 days'),
 ('ffff3333-0000-0000-0000-000000000002','ffff0000-0000-0000-0000-000000000001',2,
  current_date - 7, null),
 ('ffff3333-0000-0000-0000-000000000003','ffff0000-0000-0000-0000-000000000002',1,
  current_date - 6, null);

-- Tasks across every calendar state, so the ops page and the sync breakdown have
-- something honest to show.
insert into tasks (id, household_id, title, section, owner_member_id, weight, recurrence,
                   due_on, due_time, origin_label, created_by, created_at,
                   google_event_id, google_event_url, calendar_sync_state,
                   calendar_last_synced_at, calendar_last_error)
values
 ('ffff4444-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000001',
  'Kitchen deep clean','chore','ffff2222-0000-0000-0000-000000000001',3,'weekly',
  current_date + 1, null, null,'ffff2222-0000-0000-0000-000000000001', now() - interval '13 days',
  'evt_kitchen','https://calendar.google.com/event?eid=evt_kitchen','synced', now() - interval '40 minutes', null),
 ('ffff4444-0000-0000-0000-000000000002','ffff0000-0000-0000-0000-000000000001',
  'Take the bins out','chore','ffff2222-0000-0000-0000-000000000002',1,'every_2_days',
  current_date, null, null,'ffff2222-0000-0000-0000-000000000002', now() - interval '11 days',
  null, null,'not_scheduled', null, null),
 ('ffff4444-0000-0000-0000-000000000003','ffff0000-0000-0000-0000-000000000001',
  'Pay the water bill','admin','ffff2222-0000-0000-0000-000000000001',2,'none',
  current_date + 3, '09:30', 'Waternet','ffff2222-0000-0000-0000-000000000001', now() - interval '4 days',
  'evt_water','https://calendar.google.com/event?eid=evt_water','retry_required',
  now() - interval '2 hours','Google Calendar API: 403 rateLimitExceeded'),
 ('ffff4444-0000-0000-0000-000000000004','ffff0000-0000-0000-0000-000000000001',
  'Dentist — Joris','admin','ffff2222-0000-0000-0000-000000000002',1,'none',
  current_date + 9, '14:15','Tandarts Ceintuurbaan','ffff2222-0000-0000-0000-000000000002',
  now() - interval '3 days','evt_dentist','https://calendar.google.com/event?eid=evt_dentist',
  'external_deleted', now() - interval '1 day', null),
 ('ffff4444-0000-0000-0000-000000000005','ffff0000-0000-0000-0000-000000000001',
  'Water the plants','chore','ffff2222-0000-0000-0000-000000000002',1,'daily',
  current_date, null, null,'ffff2222-0000-0000-0000-000000000001', now() - interval '9 days',
  'evt_plants','https://calendar.google.com/event?eid=evt_plants','external_changed',
  now() - interval '5 hours', null),
 ('ffff4444-0000-0000-0000-000000000006','ffff0000-0000-0000-0000-000000000001',
  'Renew the bike insurance','admin','ffff2222-0000-0000-0000-000000000001',2,'none',
  current_date - 2, null,'Univé','ffff2222-0000-0000-0000-000000000001', now() - interval '2 days',
  null, null,'not_scheduled', null, null),
 ('ffff4444-0000-0000-0000-000000000007','ffff0000-0000-0000-0000-000000000001',
  'Hoover the stairs','chore','ffff2222-0000-0000-0000-000000000002',2,'weekly',
  null, null, null,'ffff2222-0000-0000-0000-000000000002', now() - interval '8 days',
  null, null,'not_scheduled', null, null),
 ('ffff4444-0000-0000-0000-000000000008','ffff0000-0000-0000-0000-000000000002',
  'Change the sheets','chore','ffff2222-0000-0000-0000-000000000003',2,'weekly',
  current_date + 2, null, null,'ffff2222-0000-0000-0000-000000000003', now() - interval '5 days',
  null, null,'not_scheduled', null, null),
 ('ffff4444-0000-0000-0000-000000000009','ffff0000-0000-0000-0000-000000000002',
  'Cancel the old internet contract','admin','ffff2222-0000-0000-0000-000000000003',3,'none',
  current_date + 5, null, null,'ffff2222-0000-0000-0000-000000000003', now() - interval '1 day',
  null, null,'not_scheduled', null, null);

-- An archived todo, so the "show archived" control has something behind it.
insert into tasks (id, household_id, title, section, owner_member_id, weight, recurrence,
                   created_by, created_at, archived_at, calendar_sync_state)
values ('ffff4444-0000-0000-0000-00000000000a','ffff0000-0000-0000-0000-000000000001',
  'Book the removal van','admin','ffff2222-0000-0000-0000-000000000001',2,'none',
  'ffff2222-0000-0000-0000-000000000001', now() - interval '12 days', now() - interval '6 days',
  'not_scheduled');

insert into completions (task_id, week_id, member_id, weight, completed_at) values
 ('ffff4444-0000-0000-0000-000000000001','ffff3333-0000-0000-0000-000000000001',
  'ffff2222-0000-0000-0000-000000000001',3, now() - interval '9 days'),
 ('ffff4444-0000-0000-0000-000000000007','ffff3333-0000-0000-0000-000000000001',
  'ffff2222-0000-0000-0000-000000000002',2, now() - interval '8 days'),
 ('ffff4444-0000-0000-0000-000000000007','ffff3333-0000-0000-0000-000000000002',
  'ffff2222-0000-0000-0000-000000000002',2, now() - interval '2 days');

-- Daily / every-2-day chores record one completion per occurrence (migration 008).
insert into recurring_completions (task_id, occurrence_on, member_id, weight, completed_at)
select 'ffff4444-0000-0000-0000-000000000005', d::date,
       'ffff2222-0000-0000-0000-000000000002', 1, d + interval '19 hours'
from generate_series(current_date - 8, current_date - 1, interval '1 day') d;

insert into recurring_completions (task_id, occurrence_on, member_id, weight, completed_at)
select 'ffff4444-0000-0000-0000-000000000002', d::date,
       'ffff2222-0000-0000-0000-000000000001', 1, d + interval '8 hours'
from generate_series(current_date - 10, current_date - 2, interval '2 days') d;

-- Per-member Gmail: one fresh mailbox, one that has not synced in days.
insert into google_accounts (id, household_id, member_id, email, refresh_token, connected_by,
                             calendar_id, connected_at, last_sync_at, last_sync_count,
                             client_kind, calendar_listed_at, calendar_last_sync_at)
values
 ('ffff5555-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000001',
  'ffff2222-0000-0000-0000-000000000001','mara@example.test','redacted-not-a-real-token',
  'ffff2222-0000-0000-0000-000000000001','even-sarphatipark@group.calendar.google.com',
  now() - interval '13 days', now() - interval '22 minutes', 14,'ios',
  now() - interval '13 days', now() - interval '40 minutes'),
 ('ffff5555-0000-0000-0000-000000000002','ffff0000-0000-0000-0000-000000000001',
  'ffff2222-0000-0000-0000-000000000002','joris@example.test','redacted-not-a-real-token',
  'ffff2222-0000-0000-0000-000000000002','primary',
  now() - interval '12 days', now() - interval '3 days', 0,'ios', null, null);

insert into processed_emails (household_id, member_id, gmail_message_id, actionable, processed_at, note)
select 'ffff0000-0000-0000-0000-000000000001','ffff2222-0000-0000-0000-000000000001',
       'msg-mara-' || g, (g % 4 = 0), now() - (g || ' hours')::interval, null
from generate_series(1, 48) g;

insert into processed_emails (household_id, member_id, gmail_message_id, actionable, processed_at, note)
select 'ffff0000-0000-0000-0000-000000000001','ffff2222-0000-0000-0000-000000000002',
       'msg-joris-' || g, (g % 6 = 0), now() - (g || ' hours')::interval, null
from generate_series(1, 30) g;

insert into drafts (id, household_id, from_label, subject, summary, urgency, title,
                    owner_member_id, amount_cents, due_on, reminder, status, category,
                    created_by, source_member_id, gmail_message_id, resulting_task_id,
                    resolved_at, created_at, needs_reply, suggested_reply, reply_status)
values
 ('ffff6666-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000001',
  'Waternet','Uw jaarafrekening staat klaar','€84.20 due on the 20th',2,'Pay the water bill',
  'ffff2222-0000-0000-0000-000000000001', 8420, current_date + 3,'3_days','approved','bills',
  'ffff2222-0000-0000-0000-000000000001','ffff2222-0000-0000-0000-000000000001','msg-mara-4',
  'ffff4444-0000-0000-0000-000000000003', now() - interval '4 days', now() - interval '4 days',
  false, null,'none'),
 ('ffff6666-0000-0000-0000-000000000002','ffff0000-0000-0000-0000-000000000001',
  'Tandarts Ceintuurbaan','Afspraakbevestiging','Check-up, Thursday 14:15',2,'Dentist — Joris',
  'ffff2222-0000-0000-0000-000000000002', null, current_date + 9,'1_day','approved','appointments',
  'ffff2222-0000-0000-0000-000000000002','ffff2222-0000-0000-0000-000000000002','msg-joris-6',
  'ffff4444-0000-0000-0000-000000000004', now() - interval '3 days', now() - interval '3 days',
  false, null,'none'),
 ('ffff6666-0000-0000-0000-000000000003','ffff0000-0000-0000-0000-000000000001',
  'Univé','Verlenging fietsverzekering','Renews automatically on the 1st',1,'Renew the bike insurance',
  'ffff2222-0000-0000-0000-000000000001', 4900, current_date - 2,'1_week','pending','subscriptions',
  'ffff2222-0000-0000-0000-000000000001','ffff2222-0000-0000-0000-000000000001','msg-mara-8',
  null, null, now() - interval '2 days',
  true,'Thanks — please confirm the renewal date and the new premium.','drafted'),
 ('ffff6666-0000-0000-0000-000000000004','ffff0000-0000-0000-0000-000000000001',
  'Gemeente Amsterdam','Aanslag afvalstoffenheffing','€ 342 waste levy, payable in two terms',3,
  'Pay the waste levy','ffff2222-0000-0000-0000-000000000002', 34200, current_date + 12,'1_week',
  'pending','admin','ffff2222-0000-0000-0000-000000000002','ffff2222-0000-0000-0000-000000000002',
  'msg-joris-12', null, null, now() - interval '20 hours', false, null,'none'),
 ('ffff6666-0000-0000-0000-000000000005','ffff0000-0000-0000-0000-000000000001',
  'Bol.com','Je bestelling is onderweg','Delivery Tuesday',1,'Parcel arriving',
  'ffff2222-0000-0000-0000-000000000001', null, null,'on_day','dismissed','other',
  'ffff2222-0000-0000-0000-000000000001','ffff2222-0000-0000-0000-000000000001','msg-mara-12',
  null, now() - interval '5 days', now() - interval '5 days', false, null,'none');

insert into household_invites (id, household_id, email, invited_by_member_id, status,
                               created_at, responded_at)
values
 ('ffff7777-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000002',
  'wout@example.test','ffff2222-0000-0000-0000-000000000003','pending', now() - interval '2 days', null),
 ('ffff7777-0000-0000-0000-000000000002','ffff0000-0000-0000-0000-000000000001',
  'joris@example.test','ffff2222-0000-0000-0000-000000000001','accepted',
  now() - interval '12 days', now() - interval '12 days');

insert into settlements (id, household_id, from_member_id, to_member_id, amount_cents, created_at)
values ('ffff8888-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000001',
  'ffff2222-0000-0000-0000-000000000002','ffff2222-0000-0000-0000-000000000001', 2360,
  now() - interval '7 days');

insert into expenses (id, household_id, title, amount_cents, paid_by_member_id, incurred_on,
                      settlement_id, created_at)
values
 ('ffff9999-0000-0000-0000-000000000001','ffff0000-0000-0000-0000-000000000001',
  'Groceries — Albert Heijn', 6420,'ffff2222-0000-0000-0000-000000000001', current_date - 9,
  'ffff8888-0000-0000-0000-000000000001', now() - interval '9 days'),
 ('ffff9999-0000-0000-0000-000000000002','ffff0000-0000-0000-0000-000000000001',
  'New shower curtain', 1700,'ffff2222-0000-0000-0000-000000000002', current_date - 8,
  'ffff8888-0000-0000-0000-000000000001', now() - interval '8 days'),
 ('ffff9999-0000-0000-0000-000000000003','ffff0000-0000-0000-0000-000000000001',
  'Groceries — Marqt', 4155,'ffff2222-0000-0000-0000-000000000002', current_date - 2,
  null, now() - interval '2 days'),
 ('ffff9999-0000-0000-0000-000000000004','ffff0000-0000-0000-0000-000000000001',
  'Bike lock', 2999,'ffff2222-0000-0000-0000-000000000001', current_date - 1,
  null, now() - interval '1 day');

insert into appreciations (week_id, from_member_id, to_member_id, body, said, created_at)
values ('ffff3333-0000-0000-0000-000000000001','ffff2222-0000-0000-0000-000000000002',
  'ffff2222-0000-0000-0000-000000000001','You carried the kitchen this week.', true,
  now() - interval '7 days');

commit;
