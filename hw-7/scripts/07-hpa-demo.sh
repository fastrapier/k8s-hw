#!/bin/bash
# ЧАСТЬ 3 — демонстрация HPA: нагрузка -> рост реплик -> окно стабилизации ->
# возврат к minReplicas. В конце печатает рекомендации VPA.
#
#   USERS=200 RUN_TIME=5m ./scripts/07-hpa-demo.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

LOCUSTFILE="$PROJECT_ROOT/helm/locust/files/locustfile.py"
RESULTS_DIR="$PROJECT_ROOT/locust/results"

USERS="${USERS:-200}"
SPAWN_RATE="${SPAWN_RATE:-20}"
RUN_TIME="${RUN_TIME:-5m}"
# scaleDown.stabilizationWindowSeconds в чарте = 300, поэтому по умолчанию
# ждём дольше — иначе «возврат к исходному количеству» не увидеть.
WATCH_AFTER="${WATCH_AFTER:-420}"

ensure_minikube
ensure_locust

url=$(resolve_api_url)
check_api_reachable "$url"

mkdir -p "$RESULTS_DIR"
stamp=$(date +%Y%m%d-%H%M%S)
log="$RESULTS_DIR/hpa-demo-$stamp.log"
prefix="$RESULTS_DIR/hpa-demo-$stamp"

echo "=== Демонстрация HPA ==="
kubectl get hpa "$API_DEPLOYMENT" -n "$NAMESPACE"
echo ""
echo "  нагрузка:   $USERS пользователей, spawn-rate $SPAWN_RATE, $RUN_TIME"
echo "  наблюдение: ещё ${WATCH_AFTER}s после прогона (окно стабилизации scaleDown = 300s)"
echo "  лог:        $log"
echo ""

# Наблюдатель пишет состояние HPA и число подов с таймстампами: по этому логу
# на защите видно и рост, и возврат к исходному числу реплик.
watch_state() {
  while true; do
    local ts hpa ready
    ts=$(date +%H:%M:%S)
    hpa=$(kubectl get hpa "$API_DEPLOYMENT" -n "$NAMESPACE" \
      -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}/{.spec.metrics[0].resource.target.averageUtilization} replicas={.status.currentReplicas} desired={.status.desiredReplicas}' 2>/dev/null) || hpa="n/a"
    ready=$(kubectl get pods -n "$NAMESPACE" -l "$API_SELECTOR" --no-headers 2>/dev/null | grep -c 'Running') || ready=0
    printf '[%s] cpu=%s pods_running=%s\n' "$ts" "$hpa" "$ready"
    sleep 10
  done
}

watch_state > "$log" 2>&1 &
watcher=$!
cleanup() { kill "$watcher" 2>/dev/null || true; }
trap cleanup EXIT

echo "Наблюдатель запущен (PID $watcher). Текущее состояние в другом терминале:"
echo "  tail -f $log"
echo ""

set +e
locust -f "$LOCUSTFILE" \
  --host "$url" \
  --users "$USERS" \
  --spawn-rate "$SPAWN_RATE" \
  --run-time "$RUN_TIME" \
  --headless --only-summary \
  --exit-code-on-error 0 \
  --csv "$prefix"
set -e

echo ""
echo "=== Нагрузка снята, ждём окно стабилизации (${WATCH_AFTER}s) ==="
sleep "$WATCH_AFTER"

cleanup
trap - EXIT

echo ""
echo "=== Сводка прогона ==="
"$SCRIPT_DIR/parse-stats.sh" "${prefix}_stats.csv" || true

echo ""
echo "=== Моменты, когда менялось число подов ==="
awk '
  {
    n = $NF
    sub(/^pods_running=/, "", n)
    if (n != prev) { print; prev = n }
  }
' "$log"

echo ""
echo "=== Итог HPA ==="
kubectl get hpa "$API_DEPLOYMENT" -n "$NAMESPACE"
kubectl describe hpa "$API_DEPLOYMENT" -n "$NAMESPACE" | sed -n '/Events:/,$p'

echo ""
echo "=== Рекомендации VPA ==="
if kubectl get vpa "$API_DEPLOYMENT" -n "$NAMESPACE" &>/dev/null; then
  kubectl describe vpa "$API_DEPLOYMENT" -n "$NAMESPACE" | sed -n '/Recommendation/,$p'
else
  echo "[WARN] VPA-объект не найден — выполните ./scripts/02-install-vpa.sh и ./scripts/03-build-and-deploy.sh"
fi

echo ""
echo "[OK] Демонстрация завершена. Лог: $log"
