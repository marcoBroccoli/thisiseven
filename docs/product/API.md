# evend API contract (v1)

Base URL: `http://localhost:8091` (sim) / `http://even-api.home` (LAN).
All `/v1/*` require `Authorization: Bearer <gotrue access token>`.
JSON snake_case. Money in euro cents (int). Dates `YYYY-MM-DD`, timestamps RFC3339.
Errors: `{"error": {"code": "string", "message": "human text"}}` with 4xx/5xx.

## Auth (proxied to GoTrue, standard Supabase auth API)
- `POST /auth/token?grant_type=id_token` `{provider:"apple", id_token, nonce}`
- `POST /auth/token?grant_type=password` `{email, password}` (debug accounts)
- `POST /auth/signup` `{email, password}`
- `POST /auth/token?grant_type=refresh_token` `{refresh_token}`
- `POST /auth/logout`
GoTrue mounts these under its own `/token` etc.; evend strips the `/auth` prefix.

## Objects
```
member      {id, display_name, color: "clay"|"teal", is_me}
household   {id, name, invite_code, members: [member]}
week        {id, index, started_on, closed_at?}          // index: 1,2,3…
task        {id, title, section: "chore"|"admin", owner_member_id, weight: 1|2|3,
             recurrence: "none"|"daily"|"every_2_days"|"weekly", due_on?,
             done, done_by_member_id?, meta_line}         // done = completion in open week
draft       {id, from_label, subject, summary?, urgency: 1|2|3, title,
             owner_member_id, amount_cents?, due_on?,
             reminder: "on_day"|"1_day"|"3_days"|"1_week", status, created_by_member_id}
expense     {id, title, amount_cents, paid_by_member_id, incurred_on, settled}
settlement  {id, from_member_id, to_member_id, amount_cents, created_at}
appreciation{id, from_member_id, to_member_id, body?, said}
trade       {id, task_id, task_title, from_member_id, to_member_id, accepted}
```

## Endpoints
- `GET  /healthz` → `{ok:true}` (no auth)
- `GET  /v1/me` → `{user_id, member?, household?, week?}` — member/household
  null until onboarded; drives app routing.
- `POST /v1/households` `{name, display_name}` → household (creator = clay;
  opens week 1)
- `POST /v1/households/join` `{invite_code, display_name}` → household
  (joiner = teal; 409 `household_full` on 3rd member)
- `GET  /v1/summary` → `{week, pebbles: [{member_id, weight}...ordered oldest→newest],
  percent_me, percent_partner, caption, sections: [{key:"chore"|"admin", label, tasks:[task]}],
  pending_draft_count}`  // caption per design logic
- `POST /v1/tasks` `{title, section, owner_member_id, weight, recurrence, due_on?}`
- `PATCH /v1/tasks/{id}` (same fields) · `DELETE /v1/tasks/{id}` (archives)
- `POST /v1/tasks/{id}/toggle` → task — creates/removes open-week completion
- `GET  /v1/drafts?status=pending` → `[draft]`
- `POST /v1/drafts` `{from_label, subject, summary?, urgency, title?, owner_member_id?,
  amount_cents?, due_on?, reminder?}` (title defaults to subject)
- `PATCH /v1/drafts/{id}` `{title?, owner_member_id?, amount_cents?, due_on?, reminder?}`
- `POST /v1/drafts/{id}/approve` → `{draft, task}` — tx: draft approved +
  admin task (weight 2, owner/due from draft, meta from label+due)
- `POST /v1/drafts/{id}/dismiss` → draft
- `GET  /v1/money` → `{balance_cents, debtor_member_id?, creditor_member_id?,
  feed: [{kind:"expense"|"settlement", ...expense|settlement}]}` — balance ≥ 0;
  null members when even. feed newest-first, current cycle + last settlement.
- `POST /v1/expenses` `{title, amount_cents, paid_by_member_id, incurred_on}`
- `POST /v1/settle` → money — tx: settlement for current balance, marks
  expenses settled; 409 `already_even` when balance 0.
- `GET  /v1/reset` → `{week, rows: [{key:"chores"|"admin"|"money", label,
  me_pct, partner_pct}], biggest_carry, appreciations: [appreciation],
  trades: [trade]}` — biggest_carry = computed sentence.
- `PUT  /v1/appreciations/mine` `{body?, said}` → appreciation (mine = from me
  to partner, open week; upsert)
- `POST /v1/trades` `{task_id}` → trade — hands MY task to partner (or theirs
  to me), open week
- `POST /v1/trades/{id}/accept` `{accepted: bool}` → trade — only the
  receiving side accepts
- `DELETE /v1/trades/{id}`
- `POST /v1/week/close` → `{closed_week, new_week}` — tx: apply accepted
  trades (swap task owners), delete one-off done tasks, keep recurring
  (completions archived with the closed week), open next week.

## Semantics
- Percentages: `round(100 * my_weight / total)`; 50/50 when no completions.
- Caption: empty → "Empty pans. A new week, level by definition."; |Δ|≤1 →
  "Level. Enjoy it while it lasts."; ≤4 → "Close to even. Not a competition —
  but noted."; else "Leaning <name> — mostly the admin and the remembering."
- All queries household-scoped by the authenticated member; cross-household
  access is 404, never 403.
- Solo household (partner not joined): percent_partner = 0, money endpoints
  usable, trades/appreciations 409 `no_partner`.
