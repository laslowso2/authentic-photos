#!/bin/bash
# Phase 6 discovery (READ-ONLY): shapes for qa env + dev->qa->prod pipeline + per-env bindings + HPA.
set +e
OUT="$(dirname "$0")/phase6-output.txt"
exec > >(tee "$OUT") 2>&1
sec(){ echo; echo "==================== $* ===================="; }

sec "1. Environments (copy 'development' to make 'qa')"
kubectl get environments -A
echo "--- development env yaml (spec) ---"
kubectl get environment development -n default -o yaml 2>/dev/null | sed -n '/^spec:/,$p'

sec "2. DeploymentPipeline 'default' (copy to make development->qa->production)"
kubectl get deploymentpipeline default -n default -o yaml 2>/dev/null | sed -n '/^spec:/,$p'

sec "3. Current ReleaseBinding for photos-api (releaseName + structure to model qa/prod)"
kubectl get releasebinding -n default | grep -iE 'photos-api|NAME'
kubectl get releasebinding photos-api-development -n default -o yaml 2>/dev/null | sed -n '/^spec:/,$p'

sec "4. The API Deployment: name, replicas, memory requests (needed for HPA)"
kubectl get deploy -A 2>/dev/null | grep -iE 'photos-api|NAME'
DNS=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '/photos-api/{print $1; exit}')
DNAME=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '/photos-api/{print $2; exit}')
echo "deployment: $DNS / $DNAME"
kubectl get deploy "$DNAME" -n "$DNS" -o jsonpath='{"replicas="}{.spec.replicas}{"\nrequests="}{.spec.template.spec.containers[0].resources}{"\n"}' 2>/dev/null

sec "5. Autoscaling prerequisites"
echo "--- metrics-server present? ---"
kubectl get deploy -n kube-system metrics-server 2>/dev/null || echo "   metrics-server NOT found (HPA on metrics needs it)"
echo "--- can we read live metrics? ---"
kubectl top pods -n "$DNS" 2>/dev/null | head -5 || echo "   kubectl top not available yet"
echo "--- HPA API version ---"
kubectl api-resources 2>/dev/null | grep -i horizontalpodautoscaler

sec "6. Does OpenChoreo hardcode replicas? (HPA-vs-controller check)"
kubectl get deploy "$DNAME" -n "$DNS" -o jsonpath='{.metadata.managedFields[*].manager}{"\n"}' 2>/dev/null
echo "(if a kgateway/openchoreo controller manages .spec.replicas, an HPA may conflict — we handle it)"

echo; echo "Done -> $OUT. Share it back."
