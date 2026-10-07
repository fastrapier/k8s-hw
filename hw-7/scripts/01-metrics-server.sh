#!/bin/bash
# ЧАСТЬ 1 — metrics-server: источник метрик для kubectl top, HPA и VPA.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_namespace

echo "=== metrics-server ==="
if minikube addons list -o json 2>/dev/null | grep -A2 '"metrics-server"' | grep -q '"Status": "enabled"'; then
  echo "[INFO] addon metrics-server уже включён"
else
  minikube addons enable metrics-server
  echo "[OK] addon metrics-server включён"
fi

kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s

wait_for_metrics 180

echo ""
echo "=== Метрики нод ==="
kubectl top nodes

echo ""
echo "=== Метрики подов namespace $NAMESPACE ==="
kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "[INFO] в namespace пока нет подов — это нормально до деплоя"

echo ""
echo "[OK] metrics-server готов"
