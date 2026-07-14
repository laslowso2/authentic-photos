#!/bin/bash
# Phase 4 discovery (READ-ONLY): gather ground truth for securing the API with OAuth.
# We won't guess Thunder / kgateway specifics — we read them from your cluster.
# Run:  bash phase4-discovery.sh   then share phase4-output.txt
set +e
OUT="$(dirname "$0")/phase4-output.txt"
exec > >(tee "$OUT") 2>&1
sec(){ echo; echo "==================== $* ===================="; }

sec "1. Thunder OIDC discovery (token, jwks, issuer, grants)"
curl -s http://thunder.openchoreo.localhost:8080/.well-known/openid-configuration \
  || echo "(could not reach Thunder from host — is OpenChoreo up?)"
echo

sec "2. Thunder JWKS (keys the gateway will validate tokens against)"
JWKS=$(curl -s http://thunder.openchoreo.localhost:8080/.well-known/openid-configuration | grep -o '\"jwks_uri\":\"[^\"]*\"' | cut -d'\"' -f4)
echo "jwks_uri = $JWKS"
[ -n "$JWKS" ] && curl -s "$JWKS"
echo

sec "3. How Thunder registers a CLIENT-CREDENTIALS app (from its own bootstrap script)"
echo "--- 57-service-mcp-app.sh (a machine-to-machine app example) ---"
kubectl get cm thunder-bootstrap -n thunder -o jsonpath="{.data['57-service-mcp-app.sh']}" 2>/dev/null | sed -n '1,80p'
echo "--- 52-default-apps.sh (how apps get created) ---"
kubectl get cm thunder-bootstrap -n thunder -o jsonpath="{.data['52-default-apps.sh']}" 2>/dev/null | sed -n '1,60p'

sec "4. Thunder application API base (look for the endpoint used above)"
kubectl get cm thunder-bootstrap -n thunder -o jsonpath="{.data['52-default-apps.sh']}" 2>/dev/null | grep -iE 'curl|/applications|/api|localhost|THUNDER' | head -20

sec "5. The API's gateway route (what we'll attach the JWT policy to)"
kubectl get httproutes -A | grep -iE 'photos-api|NAME'
echo "--- full route yaml ---"
kubectl get httproute -A -o yaml 2>/dev/null | grep -iE 'name:|namespace:|hostnames|parentRefs|kind: Gateway' | grep -iB1 -A4 photos 2>/dev/null | head -40

sec "6. Existing kgateway TrafficPolicies (model to copy; any JWT/auth already used?)"
kubectl get trafficpolicies.gateway.kgateway.dev -A 2>/dev/null
echo "--- any JWT config anywhere? ---"
kubectl get trafficpolicies.gateway.kgateway.dev -A -o yaml 2>/dev/null | grep -iE 'jwt|jwks|issuer|extauth|oauth' | head -20

sec "7. kgateway TrafficPolicy schema (fields available for auth/jwt)"
kubectl explain trafficpolicy.spec 2>/dev/null | head -40

echo; echo "Done -> $OUT. Share it back and I'll build the Thunder app + gateway JWT policy."
