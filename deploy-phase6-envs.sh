#!/bin/bash
# Phase 6a: create the QA environment + dev->qa->prod pipeline, and point the Project at it.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Create QA environment"
kubectl apply -f "$DIR/openchoreo/environments/qa.yaml"

echo "==> Create dev->qa->prod deployment pipeline"
kubectl apply -f "$DIR/openchoreo/environments/pipeline.yaml"

echo "==> Point the Project at the new pipeline"
kubectl apply -f "$DIR/openchoreo/project.yaml"

echo
echo "Verify:"
echo "   kubectl get environments -A"
echo "   kubectl get deploymentpipeline authentic-photos-pipeline -n default -o yaml | sed -n '/spec:/,/status/p'"
echo "Then promote the API:  bash $DIR/promote-phase6.sh qa   (later: prod)"
