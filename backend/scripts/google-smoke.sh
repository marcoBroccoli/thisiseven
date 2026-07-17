#!/bin/bash
# Google integration probe: status + manual sync.
#   ./scripts/google-smoke.sh <bearer-access-token> [base-url]
# Before consent (google-authorize.sh) sync answers 409 not_connected — expected.
set -euo pipefail

TOKEN="${1:?usage: google-smoke.sh <bearer-token> [base-url]}"
BASE="${2:-http://localhost:8091}"

echo "→ status"
curl -s "$BASE/v1/google/status" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo "→ sync"
curl -s -X POST "$BASE/v1/google/sync" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo "→ pending drafts"
curl -s "$BASE/v1/drafts?status=pending" -H "Authorization: Bearer $TOKEN" | python3 -c "
import json, sys
ds = json.load(sys.stdin)
print(f'{len(ds)} pending')
for d in ds[:10]:
    print(' •', d['from_label'], '|', d['subject'][:60], '| gmail:', d['gmail'])
"
