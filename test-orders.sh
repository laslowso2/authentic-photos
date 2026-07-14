#!/bin/bash
# Phase 5 Stage 1 test: exercise the new order/license endpoints THROUGH the gateway (dev).
# Uses a dev client-credentials token for the smoke test (a real user token comes from the SPA later).
set -uo pipefail
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"
read NS ROUTE < <(kubectl get httproute -A --no-headers 2>/dev/null | awk '/photos-api/ && $1 ~ /-development-/{print $1,$2; exit}')
HOST=$(kubectl get httproute "$ROUTE" -n "$NS" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)
BASE="http://localhost:19080/photos-api-api"

echo "==> Port-forward the data-plane gateway (19080)"
kubectl port-forward -n openchoreo-data-plane svc/gateway-default 19080:19080 >/tmp/gw-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 4

TOKEN=$(curl -s -u photos-subscriber-dev:photos-subscriber-dev-secret \
  -d grant_type=client_credentials "$TOKEN_URL" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[ -n "$TOKEN" ] || { echo "no token — run register-subscribers.sh first"; exit 1; }
H=(-H "Host: $HOST" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

echo; echo "--- GET /me ---"
curl -s "${H[@]}" "$BASE/me"; echo
echo "--- POST /orders {photoId:3} ---"
curl -s -X POST "${H[@]}" -d '{"photoId":3}' "$BASE/orders"; echo
echo "--- GET /orders ---"
curl -s "${H[@]}" "$BASE/orders"; echo
echo
echo "Expect: /me shows the subject; POST returns an orderId + license.key (UUID); GET lists it."
