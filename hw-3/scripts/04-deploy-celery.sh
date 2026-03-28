#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CELERY_ROOT="$(cd "$SCRIPT_DIR/../celery" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_werf
ensure_ghcr_login

export DOCKER_BUILDKIT=0

echo "=== Celery Broker Secret ==="
create_celery_broker_secret

echo "=== werf converge (celery) ==="
cd "$CELERY_ROOT"
werf converge --dev \
  --repo "$GHCR_REPO_CELERY" \
  --namespace "$NAMESPACE"

add_host "$CELERY_API_HOST"
add_host "$FLOWER_HOST"

echo ""
echo "[OK] Celery приложение задеплоено"
echo ""
echo "  API:    http://$CELERY_API_HOST (нужен minikube tunnel)"
echo "  Flower: http://$FLOWER_HOST (нужен minikube tunnel)"
echo ""
echo "Примеры вызова:"
echo "  curl -X POST 'http://$CELERY_API_HOST/tasks/weather?city=Moscow'"
echo "  curl -X POST 'http://$CELERY_API_HOST/tasks/news?q=technology'"
echo "  curl http://$CELERY_API_HOST/tasks/<task_id>"
