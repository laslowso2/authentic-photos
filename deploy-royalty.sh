#!/bin/bash
# Deploy the Royalty Orchestrator (publisher) + Payout Consumer (worker) and trigger their builds.
# Usage: bash deploy-royalty.sh https://github.com/<you>/authentic-photos
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
URL="${1:-}"; [ -n "$URL" ] || { echo "Usage: bash deploy-royalty.sh <repo-url>"; exit 1; }
URL="${URL%.git}"

for svc in royalty-orchestrator payout-consumer; do
  RUN="${svc}-build-$(date +%Y%m%d-%H%M%S)"
  echo "==> $svc"
  sed "s|__GIT_URL__|$URL|g" "$DIR/$svc/openchoreo/component.yaml" | kubectl apply -f -
  sed -e "s|__GIT_URL__|$URL|g" -e "s|__RUN_NAME__|$RUN|g" "$DIR/$svc/openchoreo/workflowrun.yaml" | kubectl apply -f -
  echo "   build: $RUN"
  sleep 1
done
echo
echo "Watch builds:  kubectl get workflowrun -n default -w"
echo "Then test the chain:  bash $DIR/test-royalty.sh"
