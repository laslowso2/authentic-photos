#!/bin/bash
# Phase 4/4b: attach Thunder JWT validation to EVERY Photos API route (dev/qa/prod),
# each validating only its own environment's audience (client_id) -> environments are isolated.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMPL="$DIR/api/openchoreo/gateway-jwt.yaml"

echo "==> Fetch Thunder's JWKS and reduce to fields kgateway accepts"
RAW=$(curl -s http://thunder.openchoreo.localhost:8080/oauth2/jwks)
echo "$RAW" | grep -q '"keys"' || { echo "   Could not fetch JWKS."; exit 1; }
KID=$(echo "$RAW" | grep -o '"kid":"[^"]*"' | head -1 | cut -d'"' -f4)
N=$(echo "$RAW"   | grep -o '"n":"[^"]*"'   | head -1 | cut -d'"' -f4)
E=$(echo "$RAW"   | grep -o '"e":"[^"]*"'   | head -1 | cut -d'"' -f4)
JWKS="{\"keys\":[{\"kty\":\"RSA\",\"kid\":\"$KID\",\"use\":\"sig\",\"alg\":\"RS256\",\"n\":\"$N\",\"e\":\"$E\"}]}"

echo "==> Apply a JWT policy to each photos-api route"
kubectl get httproute -A --no-headers | awk '/photos-api/{print $1, $2}' | while read -r NS ROUTE; do
  case "$NS" in
    *-development-*) AUD="photos-subscriber-dev";  ENVN="dev";;
    *-qa-*)          AUD="photos-subscriber-qa";   ENVN="qa";;
    *-production-*)  AUD="photos-subscriber-prod"; ENVN="prod";;
    *) echo "   skip (unknown env): $NS"; continue;;
  esac
  echo "   $ENVN: route=$ROUTE  ns=$NS  audience=$AUD"
  sed -e "s|__NS__|$NS|g" -e "s|__ROUTE__|$ROUTE|g" -e "s|__JWKS__|$JWKS|g" -e "s|__AUD__|$AUD|g" "$TMPL" \
    | kubectl apply -f - >/dev/null
done

echo
echo "Done. Verify isolation:  bash $DIR/test-oauth-isolation.sh"
