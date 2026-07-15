#!/bin/bash
# Deploy RabbitMQ in-cluster (dev).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> Deploying RabbitMQ..."
kubectl apply -f "$DIR/mq/rabbitmq.yaml"
kubectl rollout status deployment/rabbitmq -n authentic-photos-mq-dev --timeout=180s
echo
echo "RabbitMQ is up:  rabbitmq.authentic-photos-mq-dev.svc.cluster.local:5672  (mgmt :15672)"
echo "User: authphotos_mq   (creds in the rabbitmq-credentials secret)"
echo "Next: I'll add the DataService report + build the orchestrator/consumer."
