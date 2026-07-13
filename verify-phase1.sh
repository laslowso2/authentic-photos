#!/bin/bash
# Phase 1 verification for one environment: project exists, MySQL up, schema + seed loaded.
# Usage: bash verify-phase1.sh [dev|qa|prod]   (default: dev)
set -uo pipefail
ENV="${1:-dev}"
NS="authentic-photos-data-$ENV"

echo "==> OpenChoreo Project:"
kubectl get project authentic-photos -n default 2>/dev/null \
  && echo "   OK: project exists" || echo "   MISSING: project not found"

echo
echo "==> MySQL pod ($NS):"
kubectl get pods -n "$NS" -l app=mysql

echo
echo "==> Tables in 'authphotos':"
kubectl exec -n "$NS" statefulset/mysql -- \
  bash -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SHOW TABLES IN authphotos;"' 2>/dev/null

echo
echo "==> Sample photos (id | title | price cents | license):"
kubectl exec -n "$NS" statefulset/mysql -- \
  bash -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT id, title, price_cents, license_type FROM authphotos.photos;"' 2>/dev/null

echo
echo "==> App user can connect and count photos:"
kubectl exec -n "$NS" statefulset/mysql -- \
  bash -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -N -e "SELECT CONCAT(\"photos = \", COUNT(*)) FROM authphotos.photos;"' 2>/dev/null

echo
echo "If you see 6 photos and 4 tables (photos, customers, orders, licenses), Phase 1 ($ENV) is complete."
