#!/bin/bash
# Phase 6c: drive memory up on the dev API so the HPA scales it out.
# Requires the /alloc endpoint (rebuild the API via CI first — see PHASE6.md).
set -uo pipefail
read NS < <(kubectl get deploy -A --no-headers 2>/dev/null | awk '/photos-api-development/{print $1; exit}')
[ -n "${NS:-}" ] || { echo "dev deployment not found"; exit 1; }

echo "==> Port-forward the dev API service (8080)"
kubectl port-forward -n "$NS" svc/photos-api 8080:8080 >/tmp/api-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 3

echo "==> Allocate ~180MB in the API pod for 200s (pushes memory > 70% of 256Mi)"
curl -s "http://localhost:8080/alloc?mb=180&secs=200"; echo

echo
echo "==> Watching the HPA for 2 minutes (Ctrl-C to stop early)."
echo "    Expect TARGETS memory% to jump past 70% and REPLICAS to climb 1 -> 2+."
timeout 130 kubectl get hpa photos-api-hpa -n "$NS" -w
echo
echo "Also see the new pods:  kubectl get pods -n $NS | grep photos-api"
