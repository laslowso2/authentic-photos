#!/bin/bash
# Create the 'findw' warehouse (schema + seed) in the dev MySQL instance.
# Usage: bash apply-findw.sh [dev|qa|prod]   (default dev)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV="${1:-dev}"
NS="authentic-photos-data-$ENV"

echo "==> Applying findw schema + seed into MySQL ($NS)..."
cat "$DIR/findw/schema-findw.sql" "$DIR/findw/seed-findw.sql" \
  | kubectl exec -i -n "$NS" statefulset/mysql -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'

echo "==> Verify:"
kubectl exec -n "$NS" statefulset/mysql -- sh -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT (SELECT COUNT(*) FROM findw.dim_date) AS dates, (SELECT COUNT(*) FROM findw.dim_photo) AS photos, (SELECT COUNT(*) FROM findw.fact_sales) AS sales, (SELECT ROUND(SUM(amount_cents)/100,2) FROM findw.fact_sales) AS revenue_usd;"'
echo
echo "Warehouse ready. Deploy the DataService: bash $DIR/deploy-fin.sh <repo-url>"
