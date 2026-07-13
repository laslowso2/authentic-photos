#!/bin/bash
# Phase 3: switch the API to build-from-source and trigger a build.
# Usage: bash deploy-phase3.sh https://github.com/<you>/authentic-photos
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OC="$DIR/api/openchoreo"
URL="${1:-}"
[ -n "$URL" ] || { echo "Usage: bash deploy-phase3.sh <repo-url (no .git)>"; exit 1; }
URL="${URL%.git}"                       # normalize; OC clones fine without .git
RUN="photos-api-build-$(date +%Y%m%d-%H%M%S)"
TMP="$(mktemp -d)"

echo "==> 1/3 Update the Component to build from source ($URL)"
sed "s|__GIT_URL__|$URL|g" "$OC/component-from-source.yaml" > "$TMP/component.yaml"
kubectl apply -f "$TMP/component.yaml"

echo "==> 2/3 Trigger a build (WorkflowRun: $RUN)"
sed -e "s|__GIT_URL__|$URL|g" -e "s|__RUN_NAME__|$RUN|g" "$OC/workflowrun.yaml" > "$TMP/run.yaml"
kubectl apply -f "$TMP/run.yaml"

echo "==> 3/3 Build started. Monitor it:"
echo "   kubectl get workflowrun $RUN -n default -w"
echo "   kubectl describe workflowrun $RUN -n default        # see status.tasks step phases"
echo
echo "When WorkflowSucceeded + deployed, re-run: bash $DIR/verify-phase2.sh"
rm -rf "$TMP"
