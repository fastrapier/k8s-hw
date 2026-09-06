#!/bin/bash
# ЧАСТЬ 2 — одиночный прогон Locust с параметрами из locust/locust.conf.
#
#   USERS=200 SPAWN_RATE=20 RUN_TIME=5m ./scripts/05-locust-local.sh
#   LOCUST_TARGET=http://127.0.0.1:8080 ./scripts/05-locust-local.sh
#
# Прогон всегда headless (так задано в locust.conf). Web UI живёт в части 4 —
# его поднимает locust-operator и отдаёт через Ingress.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

LOCUSTFILE="$PROJECT_ROOT/helm/locust/files/locustfile.py"
CONFIG="$PROJECT_ROOT/locust/locust.conf"
RESULTS_DIR="$PROJECT_ROOT/locust/results"

ensure_locust

url=$(resolve_api_url)
check_api_reachable "$url"

mkdir -p "$RESULTS_DIR"
prefix="$RESULTS_DIR/run-$(date +%Y%m%d-%H%M%S)"

args=(--config "$CONFIG" -f "$LOCUSTFILE" --host "$url" --csv "$prefix")
[ -n "${USERS:-}" ]      && args+=(--users "$USERS")
[ -n "${SPAWN_RATE:-}" ] && args+=(--spawn-rate "$SPAWN_RATE")
[ -n "${RUN_TIME:-}" ]   && args+=(--run-time "$RUN_TIME")

echo "=== Locust ==="
echo "  target:     $url"
echo "  locustfile: $LOCUSTFILE"
echo "  csv:        ${prefix}_stats.csv"
echo ""
echo "Во втором терминале полезно смотреть нагрузку и реакцию HPA:"
echo "  SAMPLES=40 INTERVAL=5 ./scripts/04-measure.sh"
echo "  kubectl get hpa api -n $NAMESPACE -w"
echo ""

# exit-code-on-error=1 в конфиге: непустые failures — это провал прогона,
# но нам нужно увидеть сводку и CSV, поэтому код возврата не роняет скрипт.
set +e
locust "${args[@]}"
rc=$?
set -e

echo ""
echo "=== Сводка из CSV ==="
"$SCRIPT_DIR/parse-stats.sh" "${prefix}_stats.csv" || true

echo ""
if [ "$rc" -ne 0 ]; then
  echo "[WARN] locust завершился с кодом $rc (были ошибки запросов)"
else
  echo "[OK] прогон без ошибок"
fi
