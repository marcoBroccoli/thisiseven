#!/bin/bash
# Provision the thisiseven Supabase project (auth-only; app data lives in the
# evend docker Postgres). Idempotent: skips creation if the project exists.
#
# Usage: ./scripts/provision-supabase.sh
# Needs in ~/.env: SUPABASE_ACCESS_TOKEN, THISISEVEN_SUPABASE_DB_PASS
set -euo pipefail

source "$HOME/.env"
: "${SUPABASE_ACCESS_TOKEN:?missing}"
: "${THISISEVEN_SUPABASE_DB_PASS:?missing}"

ORG_ID="icfjctsrqggkxkrzqmhj"   # lahmacun-apps
NAME="thisiseven"
REGION="eu-central-1"
BUNDLE_ID="com.umuryavuz.even"
API="https://api.supabase.com/v1"
AUTH=(-H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN")

REF=$(curl -sf "${AUTH[@]}" "$API/projects" | python3 -c "
import json, sys
for p in json.load(sys.stdin):
    if p['name'] == '$NAME':
        print(p['id']); break
")

if [ -z "$REF" ]; then
  echo "→ creating project $NAME ($REGION, org $ORG_ID)…"
  CREATE=$(curl -sf -X POST "${AUTH[@]}" -H "Content-Type: application/json" "$API/projects" -d "{
    \"organization_id\": \"$ORG_ID\",
    \"name\": \"$NAME\",
    \"region\": \"$REGION\",
    \"db_pass\": \"$THISISEVEN_SUPABASE_DB_PASS\"
  }")
  REF=$(echo "$CREATE" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
else
  echo "→ project $NAME already exists"
fi
echo "  project ref: $REF"

echo "→ waiting for ACTIVE_HEALTHY…"
for i in $(seq 1 60); do
  STATUS=$(curl -sf "${AUTH[@]}" "$API/projects/$REF" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
  [ "$STATUS" = "ACTIVE_HEALTHY" ] && break
  sleep 10
done
echo "  status: $STATUS"

echo "→ auth config: Apple provider (native id_token) + email (debug accounts, autoconfirm)…"
curl -sf -X PATCH "${AUTH[@]}" -H "Content-Type: application/json" \
  "$API/projects/$REF/config/auth" -d "{
    \"external_apple_enabled\": true,
    \"external_apple_client_id\": \"$BUNDLE_ID\",
    \"external_email_enabled\": true,
    \"mailer_autoconfirm\": true,
    \"disable_signup\": false
  }" >/dev/null && echo "  auth config applied"

echo "→ fetching publishable key…"
KEYS=$(curl -sf "${AUTH[@]}" "$API/projects/$REF/api-keys?reveal=false")
ANON=$(echo "$KEYS" | python3 -c "
import json, sys
for k in json.load(sys.stdin):
    if k.get('type') == 'publishable' or k.get('name') in ('anon', 'publishable'):
        print(k['api_key']); break
")

echo "→ fetching legacy JWT secret (for evend HS256 verification)…"
JWT_SECRET=$(curl -s "${AUTH[@]}" "$API/projects/$REF/config/auth" | python3 -c "
import json, sys
try: print(json.load(sys.stdin).get('jwt_secret') or '')
except Exception: print('')
")

echo ""
echo "══════════════════════════════════════════════"
echo "  URL:  https://$REF.supabase.co"
echo "  KEY:  $ANON"
echo "  JWT secret: ${JWT_SECRET:+(fetched — export as THISISEVEN_SUPABASE_JWT_SECRET)}${JWT_SECRET:-(not exposed; use JWKS)}"
echo "══════════════════════════════════════════════"
