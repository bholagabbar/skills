#!/bin/bash
# Granola MCP OAuth setup script
# Performs full OAuth 2.0 PKCE flow with dynamic client registration
set -e

CONFIG_DIR="$(cd "$(dirname "$0")/.." && pwd)/../../config"
mkdir -p "$CONFIG_DIR"

OAUTH_FILE="$CONFIG_DIR/granola_oauth.json"
MCPORTER_FILE="$CONFIG_DIR/mcporter.json"
REDIRECT_URI="http://127.0.0.1:9876/callback"
SCOPE="openid email profile offline_access"

echo "[granola] Starting OAuth setup..."

# Discover OAuth endpoints
METADATA=$(curl -sf https://mcp.granola.ai/.well-known/oauth-authorization-server)
AUTH_ENDPOINT=$(echo "$METADATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['authorization_endpoint'])")
TOKEN_ENDPOINT=$(echo "$METADATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['token_endpoint'])")
REGISTER_ENDPOINT=$(echo "$METADATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['registration_endpoint'])")

# Generate PKCE
CODE_VERIFIER=$(python3 -c "import secrets; print(secrets.token_urlsafe(64)[:128])")
CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')

# Dynamic client registration
REG_RESPONSE=$(curl -sf -X POST "$REGISTER_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "{\"client_name\":\"OpenClaw Granola\",\"redirect_uris\":[\"$REDIRECT_URI\"],\"grant_types\":[\"authorization_code\",\"refresh_token\"],\"response_types\":[\"code\"],\"token_endpoint_auth_method\":\"none\"}")

CLIENT_ID=$(echo "$REG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['client_id'])")
echo "[granola] Registered client: $CLIENT_ID"

STATE=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

AUTH_URL="${AUTH_ENDPOINT}?response_type=code&client_id=${CLIENT_ID}&redirect_uri=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$REDIRECT_URI'))")&scope=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$SCOPE'))")&state=${STATE}&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256"

echo "[granola] Opening browser for sign-in..."
open "$AUTH_URL" 2>/dev/null || xdg-open "$AUTH_URL" 2>/dev/null || echo "Open this URL: $AUTH_URL"

echo "[granola] Waiting for callback on port 9876..."
RESPONSE=$(python3 -c "
import http.server, urllib.parse, sys, json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        code = params.get('code', [None])[0]
        self.send_response(200)
        self.send_header('Content-Type','text/html')
        self.end_headers()
        self.wfile.write(b'<h1>Granola auth complete! You can close this tab.</h1>')
        print(json.dumps({'code': code}))
        sys.stdout.flush()
    def log_message(self, *a): pass

s = http.server.HTTPServer(('127.0.0.1', 9876), Handler)
s.handle_request()
")

CODE=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['code'])")
echo "[granola] Got auth code, exchanging for token..."

# Exchange for token
TOKEN_RESPONSE=$(curl -sf -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&code=${CODE}&redirect_uri=${REDIRECT_URI}&client_id=${CLIENT_ID}&code_verifier=${CODE_VERIFIER}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))")
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expires_in', 21600))")

# Save OAuth credentials
python3 -c "
import json
creds = {
    'client_id': '$CLIENT_ID',
    'token_endpoint': '$TOKEN_ENDPOINT',
    'refresh_token': '$REFRESH_TOKEN',
    'access_token': '$ACCESS_TOKEN',
    'expires_in': $EXPIRES_IN
}
with open('$OAUTH_FILE', 'w') as f:
    json.dump(creds, f, indent=2)
"

# Update mcporter config
python3 -c "
import json, os
path = '$MCPORTER_FILE'
mc = json.load(open(path)) if os.path.exists(path) else {'mcpServers': {}, 'imports': []}
mc['mcpServers']['granola'] = {
    'baseUrl': 'https://mcp.granola.ai/mcp',
    'headers': {'Authorization': 'Bearer $ACCESS_TOKEN'}
}
json.dump(mc, open(path, 'w'), indent=2)
"

echo "[granola] Setup complete! Token expires in ${EXPIRES_IN}s."
echo "[granola] Config saved to $MCPORTER_FILE"
echo "[granola] OAuth creds saved to $OAUTH_FILE"
