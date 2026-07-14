#!/bin/bash
# Phase 4b: prove per-environment OAuth isolation.
# Each route should accept ONLY its own environment's token. A dev token must NOT work on prod.
set -uo pipefail
GW="http://localhost:19080"; APIPATH="/photos-api-api/photos"
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"

host_for(){ # $1 = namespace pattern
  local ns rt
  ns=$(kubectl get httproute -A --no-headers 2>/dev/null | awk -v p="$1" '/photos-api/ && $1 ~ p {print $1; exit}')
  rt=$(kubectl get httproute -A --no-headers 2>/dev/null | awk -v p="$1" '/photos-api/ && $1 ~ p {print $2; exit}')
  [ -n "$ns" ] && kubectl get httproute "$rt" -n "$ns" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null
}
token_for(){ curl -s -u "$1:$1-secret" -d grant_type=client_credentials "$TOKEN_URL" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4; }

DEV_HOST=$(host_for '-development-'); QA_HOST=$(host_for '-qa-'); PROD_HOST=$(host_for '-production-')
TDEV=$(token_for photos-subscriber-dev)
TQA=$(token_for photos-subscriber-qa)
TPROD=$(token_for photos-subscriber-prod)
[ -n "$TDEV" ] && [ -n "$TPROD" ] || { echo "Could not get tokens — run register-subscribers.sh first."; exit 1; }

echo "==> Port-forward the data-plane gateway (19080)"
kubectl port-forward -n openchoreo-data-plane svc/gateway-default 19080:19080 >/tmp/gw-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 4

code(){ curl -s -o /dev/null -w '%{http_code}' -H "Host: $1" ${2:+-H "Authorization: Bearer $2"} "$GW$APIPATH"; }
row(){ printf '%-6s  no-token=%s   dev-token=%s   qa-token=%s   prod-token=%s\n' \
  "$1" "$(code "$2")" "$(code "$2" "$TDEV")" "$(code "$2" "$TQA")" "$(code "$2" "$TPROD")"; }

echo
echo "HTTP status per (route x token). Want 200 ONLY where token env matches the route:"
echo "--------------------------------------------------------------------------------"
row "DEV"  "$DEV_HOST"
row "QA"   "$QA_HOST"
row "PROD" "$PROD_HOST"
echo "--------------------------------------------------------------------------------"
echo "PASS if: each row has 200 only under its own env's token, 401 everywhere else."
echo "The key isolation guarantee: PROD row, dev-token column = 401."
