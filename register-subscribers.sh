#!/bin/bash
# Phase 4b: register ONE OAuth subscriber client PER ENVIRONMENT in Thunder.
# Each env gets its own client_id + secret -> each token's audience differs -> envs are isolated.
# In real life the prod secret would be custody-controlled (not shared with dev/qa people).
set -uo pipefail
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"
ADMIN_ID="${ADMIN_ID:-openchoreo-system-app}"
ADMIN_SECRET="${ADMIN_SECRET:-openchoreo-system-app-secret}"

echo "==> Admin token (system app, scope=system)..."
ADMIN_TOKEN=$(curl -s -d 'grant_type=client_credentials' -d 'scope=system' \
  -d "client_id=$ADMIN_ID" -d "client_secret=$ADMIN_SECRET" "$TOKEN_URL" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[ -n "$ADMIN_TOKEN" ] || { echo "   failed to get admin token"; exit 1; }

echo "==> Port-forward thunder-service:8090..."
kubectl port-forward -n thunder svc/thunder-service 8090:8090 >/tmp/thunder-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 3

for ENV in dev qa prod; do
  CID="photos-subscriber-$ENV"
  CSEC="photos-subscriber-$ENV-secret"
  echo "==> $CID"
  EXIST=$(curl -s "http://localhost:8090/applications" -H "Authorization: Bearer $ADMIN_TOKEN")
  AID=$(echo "$EXIST" | tr '\n' ' ' \
    | grep -o "\"client_id\":\"$CID\"[^}]*\"id\":\"[^\"]*\"\|\"id\":\"[^\"]*\"[^}]*\"client_id\":\"$CID\"" \
    | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  PAYLOAD="{\"name\":\"Photos API Subscriber ($ENV)\",\"description\":\"Subscriber for $ENV\",\"inbound_auth_config\":[{\"type\":\"oauth2\",\"config\":{\"client_id\":\"$CID\",\"client_secret\":\"$CSEC\",\"grant_types\":[\"client_credentials\"],\"token_endpoint_auth_method\":\"client_secret_basic\",\"token\":{\"access_token\":{\"validity_period\":3600}}}}]}"
  if [ -n "$AID" ]; then
    curl -s -X PUT "http://localhost:8090/applications/$AID" -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H 'Content-Type: application/json' --data "$PAYLOAD" --fail-with-body >/dev/null && echo "   updated"
  else
    curl -s "http://localhost:8090/applications" -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H 'Content-Type: application/json' --data "$PAYLOAD" --fail-with-body >/dev/null && echo "   created"
  fi
done
echo
echo "Registered: photos-subscriber-dev / -qa / -prod. Now apply per-env policies: bash deploy-phase4.sh"
