#!/bin/bash
# Phase 5 Stage 3: register the web app as an OIDC PKCE public client in Thunder,
# with its redirect URI = the deployed web app URL + /callback (discovered automatically).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/web/openchoreo/thunder-web-app.json"
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"
ADMIN_ID="${ADMIN_ID:-openchoreo-system-app}"; ADMIN_SECRET="${ADMIN_SECRET:-openchoreo-system-app-secret}"

echo "==> Discover the web app URL (redirect target)"
NS=$(kubectl get httproute -A --no-headers 2>/dev/null | awk '/photos-web/{print $1; exit}')
RT=$(kubectl get httproute -A --no-headers 2>/dev/null | awk '/photos-web/{print $2; exit}')
HOST=$(kubectl get httproute "$RT" -n "$NS" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)
[ -n "$HOST" ] || { echo "   photos-web route not found"; exit 1; }
REDIRECT="http://$HOST:19080/callback"
echo "   redirect_uri = $REDIRECT"

echo "==> Admin token (scope=system)"
ADMIN_TOKEN=$(curl -s -d grant_type=client_credentials -d scope=system \
  -d "client_id=$ADMIN_ID" -d "client_secret=$ADMIN_SECRET" "$TOKEN_URL" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[ -n "$ADMIN_TOKEN" ] || { echo "   failed to get admin token"; exit 1; }

echo "==> Port-forward thunder-service:8090"
kubectl port-forward -n thunder svc/thunder-service 8090:8090 >/tmp/thunder-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 3

PAYLOAD=$(sed "s|__REDIRECT__|$REDIRECT|g" "$APP")
EXIST=$(curl -s "http://localhost:8090/applications" -H "Authorization: Bearer $ADMIN_TOKEN")
AID=$(echo "$EXIST" | tr '\n' ' ' \
  | grep -o '"client_id":"authentic-photos-web"[^}]*"id":"[^"]*"\|"id":"[^"]*"[^}]*"client_id":"authentic-photos-web"' \
  | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$AID" ]; then
  echo "==> Updating existing app ($AID)"
  curl -s -X PUT "http://localhost:8090/applications/$AID" -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H 'Content-Type: application/json' --data "$PAYLOAD" --fail-with-body >/dev/null && echo "   updated"
else
  echo "==> Creating app"
  curl -s "http://localhost:8090/applications" -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H 'Content-Type: application/json' --data "$PAYLOAD" --fail-with-body >/dev/null && echo "   created"
fi
echo
echo "Registered client 'authentic-photos-web' with redirect $REDIRECT"
