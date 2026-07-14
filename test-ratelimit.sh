#!/bin/bash
# Phase 4c test: burst ~300 requests/min at the dev Photos API and show the gateway throttle.
# Expect roughly 250 x HTTP 200, then HTTP 429 (Too Many Requests) for the rest.
set -uo pipefail
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"

read NS ROUTE < <(kubectl get httproute -A --no-headers 2>/dev/null | awk '/photos-api/ && $1 ~ /-development-/{print $1,$2; exit}')
HOST=$(kubectl get httproute "$ROUTE" -n "$NS" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)
URL="http://localhost:19080/photos-api-api/photos"
echo "Target: $HOST  (dev route)"

echo "==> Port-forward the data-plane gateway (19080)"
kubectl port-forward -n openchoreo-data-plane svc/gateway-default 19080:19080 >/tmp/gw-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 4

TOKEN=$(curl -s -u photos-subscriber-dev:photos-subscriber-dev-secret \
  -d grant_type=client_credentials "$TOKEN_URL" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[ -n "$TOKEN" ] || { echo "no token — run register-subscribers.sh first"; exit 1; }

echo "==> Firing 300 requests within the minute (25 in parallel)..."
seq 1 300 | xargs -P 25 -I{} curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: $HOST" -H "Authorization: Bearer $TOKEN" "$URL" > /tmp/rl.out 2>/dev/null

echo
echo "==> Status-code tally (expect ~250 x 200, then 429s):"
sort /tmp/rl.out | uniq -c | sed 's/^/   /'
echo
echo "If you see 200s capped near 250 and the rest 429 — local throttling works."
echo "Note: local limits are per gateway replica; with N replicas the effective cap is 250*N."
