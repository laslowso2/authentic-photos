#!/bin/bash
# Why is the JWT policy producing an invalid route? Get statuses + kgateway translation errors.
set -uo pipefail
NS=$(kubectl get httproute -A --no-headers 2>/dev/null | awk '/photos-api/{print $1; exit}')
echo "route namespace: $NS"
sec(){ echo; echo "==================== $* ===================="; }

sec "1. GatewayExtension — status conditions (Accepted?)"
kubectl get gatewayextension thunder-jwt -n "$NS" -o yaml 2>/dev/null | sed -n '/^status:/,$p'

sec "2. TrafficPolicy — status conditions (Accepted/Attached?)"
kubectl get trafficpolicy photos-api-jwt -n "$NS" -o yaml 2>/dev/null | sed -n '/^status:/,$p'

sec "3. Confirm the JWKS actually landed in the GatewayExtension (not empty/truncated)"
kubectl get gatewayextension thunder-jwt -n "$NS" -o jsonpath='{.spec.jwt.providers[0].jwks.local.inline}' 2>/dev/null | head -c 200; echo " ...(truncated)"

sec "4. kgateway controller pods"
kubectl get pods -A 2>/dev/null | grep -iE 'kgateway|NAME' | head

sec "5. kgateway controller logs (translation errors about our policy)"
for NSK in kgateway-system gwsystem openchoreo-data-plane openchoreo-control-plane kube-system; do
  P=$(kubectl get pods -n "$NSK" --no-headers 2>/dev/null | grep -i kgateway | awk '{print $1}' | head -1)
  [ -n "${P:-}" ] && { echo "--- $NSK/$P ---"; kubectl logs -n "$NSK" "$P" --tail=120 2>/dev/null | grep -iE 'jwt|thunder|photos-api|invalid|error|translat' | tail -25; }
done

echo; echo "Done. Share the output."
