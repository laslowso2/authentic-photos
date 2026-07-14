#!/bin/bash
# Pull the failure detail from a build. Usage: bash get-build-logs.sh [workflowrun-name]
set -uo pipefail
RUN="${1:-photos-api-build-20260713-093344}"

echo "==> Condition messages:"
kubectl get workflowrun "$RUN" -n default \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}' 2>/dev/null

echo; echo "==> Per-step messages (look at publish-image):"
kubectl get workflowrun "$RUN" -n default \
  -o jsonpath='{range .status.tasks[*]}{.name}: {.phase} - {.message}{"\n"}{end}' 2>/dev/null

echo; echo "==> Where the build ran (plane / namespace refs):"
kubectl get workflowrun "$RUN" -n default -o yaml 2>/dev/null \
  | grep -iE 'plane|namespace|registry|image:' | sed 's/^/   /' | head -30

echo; echo "==> Build pods still around (may be GC'd):"
kubectl get pods -A --no-headers 2>/dev/null | grep -iE "$RUN|photos-api-build" | sed 's/^/   /'

echo; echo "==> Logs from any surviving build pods (publish step is what failed):"
while read -r NS POD _; do
  [ -z "${POD:-}" ] && continue
  echo "--- $NS/$POD ---"
  kubectl logs -n "$NS" "$POD" --all-containers --tail=50 2>/dev/null | tail -50
done < <(kubectl get pods -A --no-headers 2>/dev/null | grep -iE "$RUN")
