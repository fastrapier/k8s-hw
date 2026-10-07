#!/bin/bash
# ЧАСТЬ 4 — locust-k8s-operator + чарт с LocustTest, ConfigMap и Ingress.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_namespace
check_db_schema

echo "=== Helm repo $LOCUST_OPERATOR_REPO_NAME ==="
add_helm_repo "$LOCUST_OPERATOR_REPO_NAME" "$LOCUST_OPERATOR_REPO_URL"

echo "=== Установка locust-operator ($LOCUST_OPERATOR_CHART версии $LOCUST_OPERATOR_CHART_VERSION) ==="
helm_cleanup_pending "$LOCUST_OPERATOR_RELEASE"

# На одноузловом minikube вторая реплика оператора всё равно не запустится
# из-за PDB и anti-affinity, поэтому replicaCount=1 и PDB выключен.
# Конверсионный вебхук не нужен: манифест LocustTest сразу на locust.io/v2.
helm upgrade --install "$LOCUST_OPERATOR_RELEASE" "$LOCUST_OPERATOR_CHART" \
  --version "$LOCUST_OPERATOR_CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --set replicaCount=1 \
  --set podDisruptionBudget.enabled=false \
  --set webhook.enabled=false \
  --wait --timeout 5m

echo ""
echo "=== Проверка CRD ==="
kubectl wait --for=condition=Established crd/locusttests.locust.io --timeout=60s
kubectl get crd locusttests.locust.io

echo "=== /etc/hosts ==="
add_host "$LOCUST_HOST"

echo ""
echo "=== Деплой чарта с LocustTest ==="
helm_cleanup_pending "$LOCUST_RELEASE"
helm upgrade --install "$LOCUST_RELEASE" "$PROJECT_ROOT/helm/locust" \
  --namespace "$NAMESPACE" \
  --wait --timeout 3m

echo ""
echo "=== Что создалось ==="
kubectl get locusttest -n "$NAMESPACE"
kubectl get configmap "$LOCUST_TEST_NAME-locustfile" -n "$NAMESPACE"
kubectl get svc,ingress -n "$NAMESPACE" -l app.kubernetes.io/name=locust
echo ""
echo "Job-ы и поды, созданные оператором (появляются через несколько секунд):"
kubectl get jobs,pods -n "$NAMESPACE" -l performance-test-name="$LOCUST_TEST_NAME" 2>/dev/null \
  || kubectl get jobs -n "$NAMESPACE"

echo ""
echo "[OK] Locust развёрнут в кластере"
echo "  Web UI:   http://$LOCUST_HOST  (нужен minikube tunnel)"
echo "  Логи:     kubectl logs -n $NAMESPACE job/$LOCUST_TEST_NAME-master -f"
echo "  Повторный прогон: kubectl delete locusttest $LOCUST_TEST_NAME -n $NAMESPACE && helm upgrade --install $LOCUST_RELEASE $PROJECT_ROOT/helm/locust -n $NAMESPACE"
