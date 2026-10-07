#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_helmfile
load_env

echo "=== Деплой стека мониторинга (helmfile apply) ==="
echo "[INFO] Релизы: kube-prometheus-stack, ingress-metrics, loki, promtail, grafana"
# --skip-diff-on-install: у нового релиза сравнивать не с чем, а kube-prometheus-stack
# на первой установке ещё не создал CRD, на которые ссылаются следующие релизы.
helmfile -f "$HELMFILE" apply --skip-diff-on-install --suppress-secrets

echo "=== Ожидание готовности подов ==="
kubectl wait --for=condition=Ready pod --all -n "$NAMESPACE" \
  --field-selector=status.phase!=Succeeded --timeout=600s || {
  echo "[ERROR] Не все поды готовы, текущее состояние:"
  kubectl get pods -n "$NAMESPACE"
  exit 1
}

echo "=== Записи в /etc/hosts ==="
add_host "$PROMETHEUS_HOST"
add_host "$ALERTMANAGER_HOST"
add_host "$GRAFANA_HOST"

echo ""
echo "[OK] Стек мониторинга развёрнут"
echo ""
echo "  Prometheus    http://$PROMETHEUS_HOST"
echo "  Alertmanager  http://$ALERTMANAGER_HOST"
echo "  Grafana       http://$GRAFANA_HOST   (admin / \$GRAFANA_ADMIN_PASSWORD)"
echo ""
echo "  Требуется запущенный 'minikube tunnel' в отдельном терминале."
echo "  Пароль admin: security find-generic-password -a $KEYCHAIN_ACCOUNT -s $KEYCHAIN_GRAFANA_SERVICE -w"
