#!/bin/bash
# Phase 4b discovery (READ-ONLY): confirm kgateway JWT support + how Thunder registers apps.
set +e
OUT="$(dirname "$0")/phase4b-output.txt"
exec > >(tee "$OUT") 2>&1
sec(){ echo; echo "==================== $* ===================="; }

sec "1. Does kgateway TrafficPolicy support JWT? (full spec field list)"
kubectl explain trafficpolicy.spec 2>/dev/null | grep -E '^  [a-zA-Z]' | sed 's/^/   /'
echo "--- explain jwt (if present) ---"
kubectl explain trafficpolicy.spec.jwt 2>/dev/null | head -60
echo "--- explain extAuth (fallback path) ---"
kubectl explain trafficpolicy.spec.extAuth 2>/dev/null | head -30

sec "2. Thunder JWKS (direct)"
curl -s http://thunder.openchoreo.localhost:8080/oauth2/jwks; echo

sec "3. Thunder app-registration method — bootstrap scripts (authoritative)"
for k in 52-default-apps.sh 57-service-mcp-app.sh 55-system-app.sh 54-cli-app.sh; do
  echo "----------------- $k -----------------"
  kubectl get cm thunder-bootstrap -n thunder -o go-template="{{index .data \"$k\"}}" 2>/dev/null | sed -n '1,90p'
done

sec "4. Thunder admin/bootstrap credentials (to call the app API)"
kubectl get secrets -n thunder 2>/dev/null
kubectl get cm thunder-setup-config-map -n thunder -o go-template='{{index .data "deployment.yaml"}}' 2>/dev/null | grep -iE 'client|secret|admin|password|bootstrap' | head -20

sec "5. Is DCR open? (registration endpoint expects what?)"
echo "registration_endpoint = http://thunder.openchoreo.localhost:8080/oauth2/dcr/register"
echo "(not calling it yet — we decide auth method from the scripts above)"

echo; echo "Done -> $OUT. Share it back."
