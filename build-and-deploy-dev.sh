#!/bin/bash
# Phase 2: build the API image locally, load it into k3d, and deploy it as an OC component.
# Usage: bash ~/Documents/Claude/OpenChoreo/authentic-photos/build-and-deploy-dev.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
API="$DIR/api"
TAG="authentic-photos/photos-api:0.1.0"     # non-:latest tag => k8s default pull policy is IfNotPresent
CLUSTER="openchoreo"

echo "==> 1/3 Build the container image ($TAG)"
docker build -t "$TAG" "$API"

echo "==> 2/3 Import the image into the k3d cluster (no registry needed for local dev)"
# k3d nodes run their own containerd; they can't see your local Docker images until imported.
k3d image import "$TAG" -c "$CLUSTER"

echo "==> 3/3 Apply the OpenChoreo Component + Workload"
kubectl apply -f "$API/openchoreo/component.yaml"

echo
echo "Deploying... watch the pod come up with:"
echo "   kubectl get pods -A | grep photos-api"
echo "Then verify: bash $DIR/verify-phase2.sh"
