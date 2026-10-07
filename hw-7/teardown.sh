#!/bin/bash
# Полная очистка ДЗ 7. Идемпотентен: повторный запуск ничего не ломает.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"

echo "=== Locust: чарт с LocustTest ==="
helm uninstall "$LOCUST_RELEASE" -n "$NAMESPACE" 2>/dev/null && echo "[OK] $LOCUST_RELEASE удалён" || echo "[INFO] $LOCUST_RELEASE не найден"
kubectl delete locusttest "$LOCUST_TEST_NAME" -n "$NAMESPACE" --ignore-not-found
kubectl delete job -n "$NAMESPACE" -l performance-test-name="$LOCUST_TEST_NAME" --ignore-not-found

echo "=== locust-operator ==="
helm uninstall "$LOCUST_OPERATOR_RELEASE" -n "$NAMESPACE" 2>/dev/null && echo "[OK] $LOCUST_OPERATOR_RELEASE удалён" || echo "[INFO] $LOCUST_OPERATOR_RELEASE не найден"

echo "=== Приложение (werf) ==="
cd "$ROOT_DIR"
werf dismiss --namespace "$NAMESPACE" 2>/dev/null && echo "[OK] release приложения удалён" || echo "[INFO] release приложения не найден"

echo "=== Остатки приложения ==="
kubectl delete deployment "$API_DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found
kubectl delete statefulset postgres -n "$NAMESPACE" --ignore-not-found
kubectl delete hpa "$API_DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found
kubectl delete vpa "$API_DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
kubectl delete cronjob api-cron -n "$NAMESPACE" --ignore-not-found
kubectl delete job api-migrations -n "$NAMESPACE" --ignore-not-found
kubectl delete configmap api-config postgres-config -n "$NAMESPACE" --ignore-not-found
kubectl delete secret api-credentials postgres-credentials ghcr-pull-secret -n "$NAMESPACE" --ignore-not-found
kubectl delete pvc data-postgres-0 -n "$NAMESPACE" --ignore-not-found

echo "=== VPA (контроллеры) ==="
helm uninstall "$VPA_RELEASE" -n "$NAMESPACE" 2>/dev/null && echo "[OK] $VPA_RELEASE удалён" || echo "[INFO] $VPA_RELEASE не найден"
# Helm не удаляет CRD из каталога crds/ — снимаем вручную, иначе в кластере
# остаются verticalpodautoscalers без контроллеров.
kubectl delete crd verticalpodautoscalers.autoscaling.k8s.io --ignore-not-found
kubectl delete crd verticalpodautoscalercheckpoints.autoscaling.k8s.io --ignore-not-found

echo "=== /etc/hosts ==="
remove_host "$API_HOST"
remove_host "$LOCUST_HOST"

echo ""
echo "[OK] Всё очищено."
echo "     addon metrics-server оставлен включённым (полезен и вне этого ДЗ):"
echo "       minikube addons disable metrics-server"
echo "     Namespace $NAMESPACE оставлен:"
echo "       kubectl delete namespace $NAMESPACE"
echo "     Результаты прогонов Locust остались в locust/results/ (не в git)."
