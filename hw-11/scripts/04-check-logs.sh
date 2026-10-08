#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

RENDER="$SCRIPT_DIR/lib/render.py"
trap port_forward_cleanup EXIT

ensure_minikube

echo "=== promtail ==="
kubectl get daemonset promtail -n "$NAMESPACE" \
  -o custom-columns='NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady'

# У loki-gateway нет Ingress (наружу он не нужен), поэтому только port-forward.
port_forward "svc/loki-gateway" 13100 80
BASE="http://127.0.0.1:13100"
echo "[INFO] Loki API: $BASE (port-forward на svc/loki-gateway)"

echo ""
echo "=== Готовность Loki ==="
# ReadinessProbe Loki проверяет /ready на порту 3100; gateway этот путь не проксирует.
kubectl rollout status statefulset/loki -n "$NAMESPACE" --timeout=120s

echo ""
echo "=== Метки в Loki ==="
curl -fsS --max-time 20 "$BASE/loki/api/v1/labels" | python3 "$RENDER" loki-labels

echo ""
echo "=== Значения метки namespace ==="
curl -fsS --max-time 20 "$BASE/loki/api/v1/label/namespace/values" | python3 "$RENDER" loki-labels

loki_query() {
  echo "--- $1"
  curl -fsS --max-time 30 --get "$BASE/loki/api/v1/query_range" \
    --data-urlencode "query=$1" \
    --data-urlencode 'limit=20' \
    --data-urlencode 'since=15m' \
    | python3 "$RENDER" loki-query
  echo ""
}

echo ""
echo "=== Логи через LogQL ==="
loki_query "{namespace=\"$NAMESPACE\"}"
loki_query "{namespace=\"$INGRESS_NAMESPACE\"}"
loki_query "{namespace=\"$NAMESPACE\", app=\"grafana\"}"

echo "[OK] Логи собираются promtail и доступны в Loki"
echo "[INFO] То же в UI: http://$GRAFANA_HOST/explore — datasource Loki, запрос {namespace=\"$NAMESPACE\"}"
