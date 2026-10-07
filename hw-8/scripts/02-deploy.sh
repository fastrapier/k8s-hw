#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
cd "$PROJECT_ROOT"

TAG=$(resolve_tag "${1:-}")
echo "=== Деплой $GHCR_REPO:$TAG в namespace $NAMESPACE ==="

ensure_namespace
create_ghcr_pull_secret || true
helm_cleanup_pending "$RELEASE"

PULL_SECRET_ARGS=()
if kubectl get secret ghcr-pull-secret -n "$NAMESPACE" &>/dev/null; then
  PULL_SECRET_ARGS=(--set "imagePullSecrets[0].name=ghcr-pull-secret")
fi

# Тот же чарт и тот же способ передачи тега, что и в GitHub Actions
# (.github/workflows/hw8-release.yml, job deploy).
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set "image.repository=$GHCR_REPO" \
  --set "image.tag=$TAG" \
  --set ingress.enabled=true \
  --set "ingress.host=$APP_HOST" \
  "${PULL_SECRET_ARGS[@]}" \
  --wait --timeout=5m

kubectl rollout status "deployment/$RELEASE" -n "$NAMESPACE" --timeout=300s
kubectl get pods -n "$NAMESPACE" -o wide

add_host "$APP_HOST"

echo ""
echo "[OK] Приложение задеплоено, тег образа: $TAG"
echo "[INFO] Проверка версии:"
echo "  kubectl run curl-hw8 --rm -it --restart=Never -n $NAMESPACE --image=curlimages/curl -- curl -s http://$RELEASE/version"
echo "[INFO] Через Ingress (нужен minikube tunnel): curl http://$APP_HOST/version"
