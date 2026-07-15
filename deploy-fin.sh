#!/bin/bash
# Deploy the Ballerina financial DataService (build-from-source, Ballerina buildpack) + trigger a build.
# Usage: bash deploy-fin.sh https://github.com/<you>/authentic-photos
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OC="$DIR/fin-dataservice/openchoreo"
URL="${1:-}"; [ -n "$URL" ] || { echo "Usage: bash deploy-fin.sh <repo-url>"; exit 1; }
URL="${URL%.git}"
RUN="fin-dataservice-build-$(date +%Y%m%d-%H%M%S)"

echo "==> Create/update the fin-dataservice Component (Ballerina buildpack, /fin-dataservice)"
sed "s|__GIT_URL__|$URL|g" "$OC/component.yaml" | kubectl apply -f -

echo "==> Trigger build (WorkflowRun: $RUN)"
sed -e "s|__GIT_URL__|$URL|g" -e "s|__RUN_NAME__|$RUN|g" "$OC/workflowrun.yaml" | kubectl apply -f -

echo
echo "Monitor:  kubectl get workflowrun $RUN -n default -w"
echo "Build steps: kubectl get workflowrun $RUN -n default -o jsonpath='{range .status.tasks[*]}{.name}: {.phase}{\"\\n\"}{end}'"
echo "When deployed, find the route: kubectl get httproute -A | grep fin-dataservice"
