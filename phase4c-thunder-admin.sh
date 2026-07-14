#!/bin/bash
# Phase 4c: find how to authorize app creation in Thunder (scope or console), + get jwtAuth schema.
set +e
OUT="$(dirname "$0")/phase4c-output.txt"
exec > >(tee "$OUT") 2>&1
sec(){ echo; echo "==================== $* ===================="; }
TOKEN_URL="http://thunder.openchoreo.localhost:8080/oauth2/token"
ID=openchoreo-system-app; SEC=openchoreo-system-app-secret

sec "1. What's IN the system-app token? (roles/scopes/claims)"
T=$(curl -s -d grant_type=client_credentials -d "client_id=$ID" -d "client_secret=$SEC" "$TOKEN_URL")
AT=$(echo "$T" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
P=$(echo "$AT" | cut -d. -f2); case $((${#P}%4)) in 2)P="$P==";;3)P="$P=";;esac
echo "$P" | tr '_-' '/+' | base64 -d 2>/dev/null; echo

sec "2. Does requesting scope=system change the token / help?"
curl -s -d grant_type=client_credentials -d "client_id=$ID" -d "client_secret=$SEC" -d 'scope=system' "$TOKEN_URL"; echo

sec "3. Admin USER credentials for the Thunder console (from bootstrap 50-...)"
kubectl get cm thunder-bootstrap -n thunder -o go-template='{{index .data "50-user-schema-and-users.sh"}}' 2>/dev/null \
  | grep -iE 'username|password|"email"|role|admin|OU|group' | head -50

sec "4. How is app-management permission modeled? (grep bootstrap for scope/role/permission)"
for k in 55-system-app.sh 58-workload-publisher-app.sh 56-user-mcp-app.sh 53-rca-agent-client.sh; do
  echo "--- $k ---"
  kubectl get cm thunder-bootstrap -n thunder -o go-template="{{index .data \"$k\"}}" 2>/dev/null \
    | grep -iE 'scope|role|permission|allowed|api' | head -15
done

sec "5. kgateway jwtAuth schema (for the gateway policy)"
kubectl explain trafficpolicy.spec.jwtAuth --recursive 2>/dev/null | head -80

echo; echo "Done -> $OUT. Share it back."
