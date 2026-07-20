-- An email draft may require a human reply before or alongside its todo.
-- Even stores the editable suggestion and status, but never sends mail itself.
alter table drafts add column if not exists needs_reply boolean not null default false;
alter table drafts add column if not exists suggested_reply text;
alter table drafts add column if not exists reply_text text;
alter table drafts add column if not exists reply_status text not null default 'none'
  check (reply_status in ('none', 'drafted', 'opened_in_gmail', 'sent_manually', 'done'));
