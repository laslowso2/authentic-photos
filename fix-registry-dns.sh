#!/bin/bash
# Fix: CI build pods can't resolve the image registry hostname (host.k3d.internal),
# so 'publish-image' fails. k3s reverts edits to the coredns 'NodeHosts' field, so we
# put the mapping in coredns-custom (NOT reconciled) — the same configmap restart-choreo.sh
# already uses for openchoreo.localhost. We alias host.k3d.internal -> choreo-host (the
# gateway 172.18.0.1, where the k3d serverlb publishes the registry on :10082).
set -euo pipefail

echo "==> Patching coredns-custom (host.k3d.internal -> choreo-host)..."
kubectl patch configmap coredns-custom -n kube-system --type merge \
  -p '{"data":{"k3dhost.override":"rewrite stop {\n  name exact host.k3d.internal choreo-host\n  answer auto\n}\n"}}'

echo "==> Restarting CoreDNS..."
kubectl delete pod -n kube-system -l k8s-app=kube-dns
kubectl rollout status -n kube-system deployment/coredns --timeout=60s
sleep 3

echo "==> Verify from inside the cluster (want an address + open :10082):"
kubectl run nettest --rm -i --restart=Never --image=busybox:1.36 -- sh -c \
  'echo "-- nslookup --"; nslookup host.k3d.internal 2>&1 | grep -A2 Name; \
   echo "-- tcp :10082 --"; nc -w4 -zv host.k3d.internal 10082 2>&1' 2>/dev/null || true

echo
echo "If resolution + tcp look good, re-trigger the build:"
echo "   bash $(dirname "$0")/deploy-phase3.sh https://github.com/laslowso2/authentic-photos"
