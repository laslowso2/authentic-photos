#!/bin/bash
# Register an external "subscriber" OAuth app in Thunder (client_credentials).
# Thunder's /applications API requires auth, so we first get a token as the built-in
# System Application (openchoreo-system-app) and use it as a Bearer token.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/api/openchoreo/thunder-subscriber-app.json"
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"

# Built-in system app (from Thunder bootstrap 55-system-app.sh). Override if yours differs.
ADMIN_ID="${ADMIN_ID:-openchoreo-system-app}"
ADMIN_SECRET="${ADMIN_SECRET:-openchoreo-system-app-secret}"

echo "==> 1) Get an admin token as the System Application (with scope=system)..."
ADMIN_RESP=$(curl -s -d 'grant_type=client_credentials' -d 'scope=system' \
  -d "client_id=$ADMIN_ID" -d "client_secret=$ADMIN_SECRET" "$TOKEN_URL")
ADMIN_TOKEN=$(echo "$ADMIN_RESP" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$ADMIN_TOKEN" ]; then
  echo "   FAILED to get admin token. Response was:"; echo "   $ADMIN_RESP"
  echo "   -> Either the system-app secret differs, or we need the Thunder console UI. Tell me the response."
  exit 1
fi
echo "   Got admin token."

echo "==> 2) Port-forward thunder-service:8090..."
kubectl port-forward -n thunder svc/thunder-service 8090:8090 >/tmp/thunder-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 3

echo "==> 3) Create the 'Photos API Subscriber' app (authorized)..."
curl -s --location "http://localhost:8090/applications" \
  --header "Authorization: Bearer $ADMIN_TOKEN" \
  --header 'Content-Type: application/json' \
  --data @"$APP" --fail-with-body; echo

echo
echo "If you see the created app JSON above, get a subscriber token with:"
echo "   bash $DIR/get-token.sh"
