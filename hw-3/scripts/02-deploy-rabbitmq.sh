#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_vals

echo "=== Vault login ==="
vault_login

echo "=== Рендеринг values ==="
RENDERED="/tmp/rabbitmq-values-rendered-$$.yaml"
vals eval -f "$PROJECT_ROOT/helm/rabbitmq-values.yaml" > "$RENDERED"

echo "=== Деплой RabbitMQ ==="
helm_cleanup_pending rabbitmq
helm upgrade --install rabbitmq oci://registry-1.docker.io/cloudpirates/rabbitmq \
  --namespace "$NAMESPACE" \
  --values "$RENDERED" \
  --wait --timeout=5m

rm -f "$RENDERED"

add_host "$RABBITMQ_HOST"

echo "[OK] RabbitMQ задеплоен"
echo "[INFO] Management UI: http://$RABBITMQ_HOST (нужен minikube tunnel)"
