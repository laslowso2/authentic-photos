#!/bin/bash
# Diagnose why publish-image can't reach the registry. Usage: bash diagnose-registry.sh [run-name]
set -uo pipefail
RUN="${1:-photos-api-build-20260713-103231}"

echo "==> 1. Current CoreDNS NodeHosts (should contain host.k3d.internal):"
kubectl get configmap coredns -n kube-system -o jsonpath='{.data.NodeHosts}'; echo

echo; echo "==> 2. Live DNS + TCP test from a pod (the real question):"
kubectl run nettest --rm -i --restart=Never --image=busybox:1.36 -- sh -c \
  'echo "-- nslookup host.k3d.internal --"; nslookup host.k3d.internal 2>&1; \
   echo "-- tcp connect :10082 --"; nc -w4 -zv host.k3d.internal 10082 2>&1' 2>/dev/null

echo; echo "==> 3. publish-image error for $RUN:"
kubectl get workflowrun "$RUN" -n default \
  -o jsonpath='{range .status.tasks[*]}{.name}: {.phase} - {.message}{"\n"}{end}' 2>/dev/null
while read -r NS POD _; do
  echo "--- logs: $NS/$POD (tail) ---"
  kubectl logs -n "$NS" "$POD" --all-containers --tail=20 2>/dev/null | tail -20
done < <(kubectl get pods -A --no-headers 2>/dev/null | grep -iE "${RUN}.*publish")

echo; echo "==> 4. Is a registry actually listening on the host at :10082?"
docker ps --format '{{.Names}}  {{.Ports}}' 2>/dev/null | grep -iE 'registry|10082' || echo "   (no container obviously publishing 10082 — may be a k3d registry; note what you see)"
