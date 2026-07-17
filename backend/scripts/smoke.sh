#!/bin/bash
# End-to-end smoke through the real stack on localhost:8091 —
# GoTrue signup/password grant via the /auth proxy, then the whole happy path.
set -euo pipefail
BASE="${EVEN_BASE:-http://localhost:8091}"
STAMP=$(date +%s)
A_EMAIL="smoke-ada-$STAMP@test.local"
U_EMAIL="smoke-umut-$STAMP@test.local"
PASS="smoke-pass-123"

say()  { printf '\n— %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
jqx()  { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

say "healthz"
curl -sf "$BASE/healthz" | grep -q '"ok":true' || fail healthz

say "signup Ada + Umut (GoTrue via /auth proxy)"
A_TOK=$(curl -sf -X POST "$BASE/auth/signup" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$A_EMAIL\",\"password\":\"$PASS\"}" | jqx "['access_token']") \
  || fail "ada signup"
curl -sf -X POST "$BASE/auth/signup" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$U_EMAIL\",\"password\":\"$PASS\"}" >/dev/null || fail "umut signup"
U_TOK=$(curl -sf -X POST "$BASE/auth/token?grant_type=password" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$U_EMAIL\",\"password\":\"$PASS\"}" | jqx "['access_token']") \
  || fail "umut password grant"
[ -n "$A_TOK" ] && [ -n "$U_TOK" ] || fail "empty tokens"

A() { curl -sf -H "Authorization: Bearer $A_TOK" -H 'Content-Type: application/json' "$@"; }
U() { curl -sf -H "Authorization: Bearer $U_TOK" -H 'Content-Type: application/json' "$@"; }

say "me (pre-onboarding: member is null)"
A "$BASE/v1/me" | grep -q '"member":null' || fail "me should be empty"

say "create + join household"
HOUSE=$(A -X POST "$BASE/v1/households" -d '{"name":"Smoke Huis","display_name":"Ada"}')
CODE=$(echo "$HOUSE" | jqx "['invite_code']")
ADA_ID=$(echo "$HOUSE" | jqx "['members'][0]['id']")
JOIN=$(U -X POST "$BASE/v1/households/join" -d "{\"invite_code\":\"$CODE\",\"display_name\":\"Umut\"}")
UMUT_ID=$(echo "$JOIN" | jqx "['members'][1]['id']")
echo "  invite $CODE ada=$ADA_ID umut=$UMUT_ID"

say "tasks + toggle + summary"
T1=$(A -X POST "$BASE/v1/tasks" -d "{\"title\":\"Laundry\",\"section\":\"chore\",\"owner_member_id\":\"$ADA_ID\",\"weight\":2,\"recurrence\":\"weekly\"}" | jqx "['id']")
A -X POST "$BASE/v1/tasks/$T1/toggle" >/dev/null
PCT=$(A "$BASE/v1/summary" | jqx "['percent_me']")
[ "$PCT" = "100" ] || fail "summary pct $PCT != 100"

say "draft propose → approve"
D1=$(U -X POST "$BASE/v1/drafts" -d "{\"from_label\":\"Vattenfall\",\"subject\":\"July bill\",\"urgency\":2,\"amount_cents\":11240,\"owner_member_id\":\"$UMUT_ID\",\"due_on\":\"2026-07-25\"}" | jqx "['id']")
A -X POST "$BASE/v1/drafts/$D1/approve" | grep -q '"section": *"admin"' \
  || A -X GET "$BASE/v1/drafts?status=approved" | grep -q "$D1" || fail "approve"

say "money: expenses + settle"
A -X POST "$BASE/v1/expenses" -d "{\"title\":\"Groceries\",\"amount_cents\":8620,\"paid_by_member_id\":\"$ADA_ID\"}" >/dev/null
BAL=$(U -X POST "$BASE/v1/expenses" -d "{\"title\":\"Internet\",\"amount_cents\":3999,\"paid_by_member_id\":\"$UMUT_ID\"}" | jqx "['balance_cents']")
[ "$BAL" = "2311" ] || fail "balance $BAL != 2311"
U -X POST "$BASE/v1/settle" | grep -q '"balance_cents": *0' || fail settle

say "reset: appreciation, trade, close"
A -X PUT "$BASE/v1/appreciations/mine" -d '{"body":"Noticed.","said":true}' >/dev/null
TR=$(A -X POST "$BASE/v1/trades" -d "{\"task_id\":\"$T1\"}" | jqx "['id']")
U -X POST "$BASE/v1/trades/$TR/accept" -d '{"accepted":true}' >/dev/null
WK=$(A "$BASE/v1/reset" | jqx "['week']['id']")
A -X POST "$BASE/v1/week/close" -d "{\"week_id\":\"$WK\"}" | grep -q '"new_week"' || fail close
NEWPCT=$(A "$BASE/v1/summary" | jqx "['percent_me']")
[ "$NEWPCT" = "50" ] || fail "post-close pct $NEWPCT != 50"

printf '\nSMOKE OK — %s\n' "$BASE"
