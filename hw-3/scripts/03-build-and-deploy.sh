#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_ROOT="$(cd "$SCRIPT_DIR/../go" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_werf
ensure_ghcr_login

export DOCKER_BUILDKIT=0

echo "=== Vault AppRole Secret ==="
create_vault_approle_secret

echo "=== ghcr.io imagePullSecret ==="
create_ghcr_pull_secret

echo "=== werf converge (go) ==="
cd "$GO_ROOT"
werf converge --dev \
  --repo "$GHCR_REPO" \
  --namespace "$NAMESPACE"

echo ""
echo "[OK] Приложение задеплоено через werf"
echo ""
echo "Producer CronJob-ы запускаются каждые 2 минуты."
echo "Для просмотра логов consumer-ов:"
echo "  kubectl logs -f deployment/consumer-weather -n $NAMESPACE"
echo "  kubectl logs -f deployment/consumer-news -n $NAMESPACE"
