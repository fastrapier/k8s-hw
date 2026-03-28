#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"
source "$SCRIPT_DIR/common.sh"

echo "=== Удаление Celery приложения (werf) ==="
cd "$(dirname "${BASH_SOURCE[0]}")/celery" 2>/dev/null && \
  werf dismiss --namespace "$NAMESPACE" 2>/dev/null && echo "[OK] celery release удалён" || echo "[INFO] celery release не найден"
cd - &>/dev/null

echo "=== Удаление Go приложения (werf) ==="
cd "$(dirname "${BASH_SOURCE[0]}")/go" 2>/dev/null && \
  werf dismiss --namespace "$NAMESPACE" 2>/dev/null && echo "[OK] go release удалён" || echo "[INFO] go release не найден"
cd - &>/dev/null

echo "=== Очистка оставшихся ресурсов ==="
kubectl delete deployment consumer-weather consumer-news celery-worker celery-api flower -n "$NAMESPACE" --ignore-not-found
kubectl delete cronjob -n "$NAMESPACE" -l app=producer --ignore-not-found
kubectl delete job -n "$NAMESPACE" -l app=producer --ignore-not-found
kubectl delete service celery-api flower -n "$NAMESPACE" --ignore-not-found
kubectl delete ingress celery-api flower -n "$NAMESPACE" --ignore-not-found
kubectl delete configmap app-config celery-config -n "$NAMESPACE" --ignore-not-found

echo "=== Удаление K8s Secrets ==="
kubectl delete secret vault-approle ghcr-pull-secret celery-broker -n "$NAMESPACE" --ignore-not-found

echo "=== Удаление RabbitMQ ==="
helm uninstall rabbitmq -n "$NAMESPACE" 2>/dev/null && echo "[OK] RabbitMQ удалён" || echo "[INFO] RabbitMQ release не найден"

echo "=== Удаление Vault ==="
helm uninstall vault -n "$NAMESPACE" 2>/dev/null && echo "[OK] Vault удалён" || echo "[INFO] Vault release не найден"
kubectl delete pvc -n "$NAMESPACE" -l app.kubernetes.io/name=vault --ignore-not-found

echo "=== Очистка /etc/hosts ==="
for h in "$VAULT_HOST" "$RABBITMQ_HOST" "$CELERY_API_HOST" "$FLOWER_HOST"; do
  if grep -q "$h" /etc/hosts 2>/dev/null; then
    sudo sed -i '' "/$h/d" /etc/hosts
    echo "[OK] $h удалён из /etc/hosts"
  fi
done

echo ""
echo "[OK] Всё очищено. Namespace $NAMESPACE остался (может содержать PVC)."
echo "     Для полного удаления: kubectl delete namespace $NAMESPACE"
echo "     Для остановки кластера: minikube stop"
