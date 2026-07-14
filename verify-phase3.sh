#!/bin/bash
# Phase 3 verification: did the source build succeed AND replace the running image?
set -uo pipefail

echo "==> WorkflowRuns for photos-api:"
kubectl get workflowrun -n default -l openchoreo.dev/component=photos-api 2>/dev/null

LATEST=$(kubectl get workflowrun -n default -l openchoreo.dev/component=photos-api \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null)
echo; echo "==> Latest build: ${LATEST:-<none>}"

if [ -n "${LATEST:-}" ]; then
  echo "--- conditions (want WorkflowSucceeded=True) ---"
  kubectl get workflowrun "$LATEST" -n default \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}' 2>/dev/null
  echo "--- build steps ---"
  kubectl get workflowrun "$LATEST" -n default \
    -o jsonpath='{range .status.tasks[*]}{.name}: {.phase}{"\n"}{end}' 2>/dev/null
fi

echo; echo "==> Running API pod + image (the decisive check):"
read NS POD < <(kubectl get pods -A --no-headers 2>/dev/null | awk '/photos-api/ && !/build/{print $1,$2; exit}')
if [ -n "${POD:-}" ]; then
  echo "   pod:   $POD"
  echo "   age:   $(kubectl get pod "$POD" -n "$NS" --no-headers | awk '{print $5}')"
  echo "   image: $(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].image}')"
  echo
  echo "   If image is 'authentic-photos/photos-api:0.1.0' -> still the Phase 2 image (build not deployed yet)."
  echo "   If image is an OpenChoreo registry path / has a digest -> Phase 3 build is live. "
else
  echo "   API pod not found."
fi
