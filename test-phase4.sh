#!/bin/bash
# Phase 4 test: prove the API is OAuth-protected AT THE GATEWAY.
# (We must go through the gateway, not port-forward the pod, since that's where JWT is enforced.)
set -uo pipefail
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"

echo "==> Locate the route + its hostname/path"
read NS ROUTE < <(kubectl get httproute -A --no-headers 2>/dev/null | awk '/photos-api/{print $1,$2; exit}')
HOST=$(kubectl get httproute "$ROUTE" -n "$NS" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)
PREFIX=$(kubectl get httproute "$ROUTE" -n "$NS" -o jsonpath='{.spec.rules[0].matches[0].path.value}' 2>/dev/null)
PREFIX="${PREFIX%/}"
URL="http://localhost:19080${PREFIX}/photos"
echo "   route=$ROUTE  host=$HOST  path=${PREFIX}/photos"

echo "==> Port-forward the data-plane gateway (19080)"
kubectl port-forward -n openchoreo-data-plane svc/gateway-default 19080:19080 >/tmp/gw-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 4

echo
echo "==> 1) Call WITHOUT a token  (expect 401 Unauthorized):"
curl -s -o /dev/null -w '   HTTP %{http_code}\n' -H "Host: $HOST" "$URL"

echo "==> 2) Get a subscriber token from Thunder:"
TOKEN=$(curl -s -u photos-subscriber:photos-subscriber-secret \
  -d 'grant_type=client_credentials' "$TOKEN_URL" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[ -n "$TOKEN" ] && echo "   got token (${#TOKEN} chars)" || { echo "   FAILED to get token"; exit 1; }

echo "==> 3) Call WITH the token  (expect 200 + 6 photos):"
curl -s -w '\n   HTTP %{http_code}\n' -H "Host: $HOST" -H "Authorization: Bearer $TOKEN" "$URL"

echo
echo "401 then 200 = OAuth-protected API working. External subscribers now need a Thunder token."
