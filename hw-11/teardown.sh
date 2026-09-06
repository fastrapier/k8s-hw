#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"
source "$SCRIPT_DIR/common.sh"

# CRD Prometheus Operator по умолчанию остаются: helm их не удаляет, а сносить
# их вместе с ресурсами других ДЗ рискованно. Удаление — только по флагу.
DELETE_CRDS=false
if [ "${1:-}" = "--crds" ]; then
  DELETE_CRDS=true
fi

sudo -v

echo "=== Удаление релизов (helmfile destroy) ==="
if command -v helmfile &>/dev/null; then
  # values-файлы Grafana требуют env даже на destroy: helmfile рендерит их
  # перед тем, как понять, что удаляет. Значения тут не используются.
  GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-teardown}" \
  GRAFANA_SMTP_PASSWORD="${GRAFANA_SMTP_PASSWORD:-teardown}" \
  GRAFANA_SMTP_USER="${GRAFANA_SMTP_USER:-teardown@example.com}" \
    helmfile -f "$HELMFILE" destroy 2>/dev/null && echo "[OK] релизы удалены" \
    || echo "[INFO] helmfile destroy отработал с ошибками (часть релизов могла отсутствовать)"
else
  echo "[INFO] helmfile не установлен, удаляю релизы через helm"
  for release in grafana promtail loki ingress-metrics kube-prometheus-stack; do
    helm uninstall "$release" -n "$NAMESPACE" 2>/dev/null \
      && echo "[OK] $release удалён" || echo "[INFO] $release не найден"
  done
fi

echo "=== Очистка оставшихся ресурсов ==="
kubectl delete service ingress-metrics -n "$INGRESS_NAMESPACE" --ignore-not-found
kubectl delete pvc -n "$NAMESPACE" --all --ignore-not-found
# Prometheus Operator создаёт этот Secret сам, helm его не отслеживает.
kubectl delete secret -n "$NAMESPACE" \
  prometheus-kube-prometheus-stack-prometheus \
  alertmanager-kube-prometheus-stack-alertmanager-generated \
  --ignore-not-found

if [ "$DELETE_CRDS" = true ]; then
  echo "=== Удаление CRD Prometheus Operator ==="
  echo "[WARN] CRD общие на весь кластер — это сломает мониторинг в других namespace"
  for crd in \
    alertmanagerconfigs.monitoring.coreos.com \
    alertmanagers.monitoring.coreos.com \
    podmonitors.monitoring.coreos.com \
    probes.monitoring.coreos.com \
    prometheusagents.monitoring.coreos.com \
    prometheuses.monitoring.coreos.com \
    prometheusrules.monitoring.coreos.com \
    scrapeconfigs.monitoring.coreos.com \
    servicemonitors.monitoring.coreos.com \
    thanosrulers.monitoring.coreos.com; do
    kubectl delete crd "$crd" --ignore-not-found
  done
else
  echo "=== CRD Prometheus Operator оставлены ==="
  echo "[INFO] Для полного удаления: ./teardown.sh --crds"
fi

echo "=== Очистка /etc/hosts ==="
remove_host "$PROMETHEUS_HOST"
remove_host "$ALERTMANAGER_HOST"
remove_host "$GRAFANA_HOST"

echo ""
echo "[OK] Всё очищено. Namespace $NAMESPACE остался."
echo "     Для полного удаления: kubectl delete namespace $NAMESPACE"
echo "     Addon ingress не отключался: minikube addons disable ingress"
