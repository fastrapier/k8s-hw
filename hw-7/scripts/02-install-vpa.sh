#!/bin/bash
# ЧАСТЬ 3 — контроллеры VPA (Fairwinds chart).
#
# Идёт ДО деплоя приложения, потому что чарт приносит CRD
# verticalpodautoscalers.autoscaling.k8s.io, а в .helm/ есть объект
# VerticalPodAutoscaler: без CRD werf converge упал бы на неизвестном kind.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_namespace

echo "=== Helm repo $VPA_REPO_NAME ==="
add_helm_repo "$VPA_REPO_NAME" "$VPA_REPO_URL"

echo "=== Установка VPA ($VPA_CHART версии $VPA_CHART_VERSION) ==="
helm_cleanup_pending "$VPA_RELEASE"

# metrics-server ставится отдельно addon-ом minikube, поэтому подчарт чарта
# отключён — иначе в кластере оказались бы два metrics-server.
helm upgrade --install "$VPA_RELEASE" "$VPA_CHART" \
  --version "$VPA_CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --set metrics-server.enabled=false \
  --set recommender.enabled=true \
  --set updater.enabled=true \
  --set admissionController.enabled=true \
  --wait --timeout 5m

echo ""
echo "=== Проверка CRD ==="
kubectl wait --for=condition=Established crd/verticalpodautoscalers.autoscaling.k8s.io --timeout=60s
kubectl get crd | grep autoscaling.k8s.io

echo ""
echo "=== Поды VPA ==="
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$VPA_RELEASE"

echo ""
echo "[OK] VPA установлен. Рекомендации появляются через 5-15 минут работы под нагрузкой."
