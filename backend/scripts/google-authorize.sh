#!/bin/bash
# One-time Google consent for the household account.
#   ./scripts/google-authorize.sh <bearer-access-token> [base-url]
# Prints the consent URL, catches the loopback redirect on 127.0.0.1:8123,
# then calls POST /v1/google/connect with the caller's bearer token.
set -euo pipefail

TOKEN="${1:?usage: google-authorize.sh <bearer-token> [base-url]}"
BASE="${2:-http://localhost:8091}"
REDIRECT="http://127.0.0.1:8123/oauth/callback"

CLIENT_ID=$(grep '^GOOGLE_OAUTH_CLIENT_ID=' "$(dirname "$0")/../.env" | cut -d= -f2-)
[ -n "$CLIENT_ID" ] || { echo "GOOGLE_OAUTH_CLIENT_ID missing from backend/.env"; exit 1; }

SCOPE="https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.events openid email profile"
AUTH_URL="https://accounts.google.com/o/oauth2/v2/auth?client_id=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],''))" "$CLIENT_ID")&redirect_uri=$(python3 -c "import urllib.parse;print(urllib.parse.quote('$REDIRECT',''))")&response_type=code&scope=$(python3 -c "import urllib.parse;print(urllib.parse.quote('$SCOPE',''))")&access_type=offline&prompt=consent"

echo ""
echo "Open this URL in a browser signed into the HOUSEHOLD Google account:"
echo ""
echo "$AUTH_URL"
echo ""
echo "Waiting for the redirect on $REDIRECT …"

CODE=$(python3 - <<'PYEOF'
import http.server, urllib.parse, sys

class H(http.server.BaseHTTPRequestHandler):
    code = None
    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        H.code = (q.get("code") or [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(b"<h2>Even is connected. You can close this tab.</h2>")
    def log_message(self, *a): pass

srv = http.server.HTTPServer(("127.0.0.1", 8123), H)
while H.code is None:
    srv.handle_request()
print(H.code)
PYEOF
)

[ -n "$CODE" ] || { echo "No code received"; exit 1; }
echo "Code received — exchanging via evend…"

curl -sf -X POST "$BASE/v1/google/connect" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$CODE\", \"redirect_uri\": \"$REDIRECT\"}" | python3 -m json.tool
