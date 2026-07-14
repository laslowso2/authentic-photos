#!/bin/bash
# Phase 5 Stage 2: deploy the web app as an OpenChoreo web-application (build-from-source) + trigger a build.
# Usage: bash deploy-web.sh https://github.com/<you>/authentic-photos
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OC="$DIR/web/openchoreo"
URL="${1:-}"; [ -n "$URL" ] || { echo "Usage: bash deploy-web.sh <repo-url>"; exit 1; }
URL="${URL%.git}"
RUN="photos-web-build-$(date +%Y%m%d-%H%M%S)"
TMP="$(mktemp -d)"

echo "==> Create/update the web Component (build from $URL /web)"
sed "s|__GIT_URL__|$URL|g" "$OC/component.yaml" | kubectl apply -f -

echo "==> Trigger build (WorkflowRun: $RUN)"
sed -e "s|__GIT_URL__|$URL|g" -e "s|__RUN_NAME__|$RUN|g" "$OC/workflowrun.yaml" | kubectl apply -f -
rm -rf "$TMP"

echo
echo "Monitor:  kubectl get workflowrun $RUN -n default -w"
echo "When it's WorkflowSucceeded + deployed, get the web app URL:"
echo "  kubectl get httproute -A | grep photos-web"
echo "Then we do Stage 3 (register that URL as the Thunder redirect + gateway audience/CORS)."
