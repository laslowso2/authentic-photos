#!/bin/bash
# Get a client-credentials access token from Thunder (as an external subscriber would),
# then decode its claims so you can see issuer / audience / expiry.
set -uo pipefail
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"
CLIENT_ID="photos-subscriber"
CLIENT_SECRET="photos-subscriber-secret"

echo "==> Requesting token (grant_type=client_credentials, client_secret_basic)..."
RESP=$(curl -s -u "$CLIENT_ID:$CLIENT_SECRET" \
  -d 'grant_type=client_credentials' "$TOKEN_URL")
echo "$RESP"

TOKEN=$(echo "$RESP" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$TOKEN" ]; then echo "No access_token returned — check the response above."; exit 1; fi

echo
echo "==> Decoded JWT claims (payload):"
PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
# base64url -> base64, pad, decode
case $(( ${#PAYLOAD} % 4 )) in 2) PAYLOAD="${PAYLOAD}==";; 3) PAYLOAD="${PAYLOAD}=";; esac
echo "$PAYLOAD" | tr '_-' '/+' | base64 -d 2>/dev/null; echo

echo
echo "==> Export it for the API test:"
echo "   export TOKEN='$TOKEN'"
