#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"
source "$SCRIPT_DIR/common.sh"

echo "=== Удаление приложения (werf) ==="
cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && \
  werf dismiss --namespace "$NAMESPACE" 2>/dev/null && echo "[OK] release удалён" || echo "[INFO] release не найден"

echo "=== Очистка оставшихся ресурсов ==="
kubectl delete deployment consumer-weather consumer-news -n "$NAMESPACE" --ignore-not-found
kubectl delete cronjob -n "$NAMESPACE" -l app=producer --ignore-not-found
kubectl delete job -n "$NAMESPACE" -l app=producer --ignore-not-found
kubectl delete configmap app-config -n "$NAMESPACE" --ignore-not-found

echo "=== Удаление K8s Secrets ==="
kubectl delete secret vault-approle ghcr-pull-secret -n "$NAMESPACE" --ignore-not-found

echo "=== Удаление RedisInsight ==="
helm uninstall redisinsight -n "$NAMESPACE" 2>/dev/null && echo "[OK] RedisInsight удалён" || echo "[INFO] RedisInsight не найден"

echo "=== Удаление Redis ==="
kubectl delete statefulset redis -n "$NAMESPACE" --ignore-not-found
kubectl delete service redis redis-headless -n "$NAMESPACE" --ignore-not-found
kubectl delete pvc redis-data-redis-0 -n "$NAMESPACE" --ignore-not-found

echo "=== Удаление RabbitMQ ==="
helm uninstall rabbitmq -n "$NAMESPACE" 2>/dev/null && echo "[OK] RabbitMQ удалён" || echo "[INFO] RabbitMQ не найден"

echo "=== Удаление Vault ==="
helm uninstall vault -n "$NAMESPACE" 2>/dev/null && echo "[OK] Vault удалён" || echo "[INFO] Vault не найден"
kubectl delete pvc -n "$NAMESPACE" -l app.kubernetes.io/name=vault --ignore-not-found

echo "=== Очистка /etc/hosts ==="
for h in "$VAULT_HOST" "$RABBITMQ_HOST" "$REDIS_HOST"; do
  if grep -q "$h" /etc/hosts 2>/dev/null; then
    sudo sed -i '' "/$h/d" /etc/hosts
    echo "[OK] $h удалён из /etc/hosts"
  fi
done

echo ""
echo "[OK] Всё очищено. Namespace $NAMESPACE остался (может содержать PVC)."
echo "     Для полного удаления: kubectl delete namespace $NAMESPACE"
