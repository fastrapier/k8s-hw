#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube

echo "=== Namespace $NAMESPACE ==="
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== Helm repo sonarqube ==="
add_helm_repo sonarqube https://SonarSource.github.io/helm-chart-sonarqube

echo ""
echo "=== Passcode мониторинга ==="
# Чарт не соберётся без monitoringPasscode (жёсткая валидация в шаблонах).
# В values его не кладём: это секрет, а values уезжают в репозиторий.
MONITORING_PASSCODE="$(keychain_get_or_create "$KEYCHAIN_PASSCODE_SERVICE")"
echo "[OK] passcode взят из Keychain ($KEYCHAIN_PASSCODE_SERVICE)"

echo ""
echo "=== Деплой SonarQube (Community Build) ==="
helm_cleanup_pending "$SONAR_RELEASE"

# --timeout 15m: первый старт распаковывает бандл и поднимает встроенный
# Elasticsearch, на minikube это заметно дольше дефолтных 5 минут.
helm upgrade --install "$SONAR_RELEASE" sonarqube/sonarqube \
  --namespace "$NAMESPACE" \
  --version "$SONAR_CHART_VERSION" \
  --values "$SCRIPT_DIR/../helm/sonarqube-values.yaml" \
  --set monitoringPasscode="$MONITORING_PASSCODE" \
  --wait --timeout 15m

echo ""
echo "=== Готовность ==="
kubectl rollout status "statefulset/$SONAR_SVC" -n "$NAMESPACE" --timeout=900s

add_host "$SONAR_HOST"

echo ""
echo "[OK] SonarQube задеплоен"
echo "[INFO] UI:                http://$SONAR_HOST (нужен minikube tunnel)"
echo "[INFO] Внутри кластера:   $SONAR_IN_CLUSTER_URL"
echo "[INFO] Логин по умолчанию: admin / admin (пароль сменит 03-configure-sonarqube.sh)"
