#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

RENDER="$SCRIPT_DIR/lib/render.py"
trap port_forward_cleanup EXIT

ensure_minikube

echo "=== Генерация трафика через ingress ==="
# Метрика nginx_ingress_controller_requests появляется только после первого
# обработанного запроса — до этого запрос в Prometheus вернёт пустой результат.
for _ in $(seq 1 20); do
  curl -fsS --max-time 3 "http://$PROMETHEUS_HOST/-/ready" &>/dev/null || true
  curl -fsS --max-time 3 "http://$GRAFANA_HOST/api/health" &>/dev/null || true
done
echo "[OK] Отправлено ~40 запросов через ingress-nginx"

BASE="$(prometheus_base_url)"
echo "[INFO] Prometheus API: $BASE"

echo ""
echo "=== Состояние таргета ingress-metrics ==="
curl -fsS --max-time 15 --get "$BASE/api/v1/targets" --data-urlencode 'state=active' \
  | python3 "$RENDER" prom-targets

prom_query() {
  echo "--- $1"
  curl -fsS --max-time 15 --get "$BASE/api/v1/query" --data-urlencode "query=$1" \
    | python3 "$RENDER" prom-query
  echo ""
}

echo ""
echo "=== Запрос метрик nginx ==="
prom_query 'nginx_ingress_controller_requests'
prom_query 'sum by (ingress, status) (nginx_ingress_controller_requests)'
prom_query 'sum(rate(nginx_ingress_controller_requests[1m]))'
prom_query 'histogram_quantile(0.95, sum by (le) (rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])))'
prom_query 'nginx_ingress_controller_nginx_process_connections'

echo "[OK] Метрики ingress-nginx собираются Prometheus"
echo "[INFO] То же в UI: http://$PROMETHEUS_HOST/graph — запрос nginx_ingress_controller_requests"
