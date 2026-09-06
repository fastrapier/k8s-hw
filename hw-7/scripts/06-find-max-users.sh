#!/bin/bash
# ЧАСТЬ 2 — поиск максимума пользователей, которых приложение обрабатывает
# корректно: ступенчатые прогоны Locust, пока не появятся ошибки или
# avg не превысит порог.
#
#   STEPS="10 25 50 100 200 400" STEP_RUN_TIME=1m MAX_AVG_MS=5000 ./scripts/06-find-max-users.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

LOCUSTFILE="$PROJECT_ROOT/helm/locust/files/locustfile.py"
RESULTS_DIR="$PROJECT_ROOT/locust/results"

STEPS="${STEPS:-10 25 50 100 200 400}"
STEP_RUN_TIME="${STEP_RUN_TIME:-1m}"
SPAWN_RATE="${SPAWN_RATE:-10}"
# Порог из задания: среднее время ответа должно оставаться < 5-7 секунд.
MAX_AVG_MS="${MAX_AVG_MS:-5000}"
# Пауза между ступенями, чтобы HPA и приложение вернулись в исходное состояние.
COOLDOWN="${COOLDOWN:-30}"

ensure_locust

url=$(resolve_api_url)
check_api_reachable "$url"

mkdir -p "$RESULTS_DIR"
stamp=$(date +%Y%m%d-%H%M%S)

echo "=== Ступенчатый поиск максимума ==="
echo "  target:     $url"
echo "  ступени:    $STEPS"
echo "  на ступень: $STEP_RUN_TIME (spawn-rate $SPAWN_RATE)"
echo "  порог avg:  ${MAX_AVG_MS} ms, ошибок: 0"
echo ""
printf '%8s %10s %8s %10s %10s %10s %s\n' "USERS" "REQS" "FAILS" "AVG_MS" "P95_MS" "RPS" "ВЕРДИКТ"

best=""
for users in $STEPS; do
  prefix="$RESULTS_DIR/step-$stamp-u$users"

  set +e
  locust -f "$LOCUSTFILE" \
    --host "$url" \
    --users "$users" \
    --spawn-rate "$SPAWN_RATE" \
    --run-time "$STEP_RUN_TIME" \
    --headless --only-summary \
    --exit-code-on-error 0 \
    --csv "$prefix" >/dev/null 2>&1
  set -e

  if ! stats=$("$SCRIPT_DIR/parse-stats.sh" "${prefix}_stats.csv" --tsv 2>/dev/null); then
    printf '%8s %10s %8s %10s %10s %10s %s\n' "$users" "-" "-" "-" "-" "-" "НЕТ ДАННЫХ — стоп"
    break
  fi

  IFS=$'\t' read -r reqs fails avg p95 rps <<< "$stats"

  verdict="ok"
  failed=0
  if [ "$fails" -gt 0 ]; then
    verdict="ОШИБКИ ЗАПРОСОВ"
    failed=1
  elif [ "$avg" -gt "$MAX_AVG_MS" ]; then
    verdict="AVG > ${MAX_AVG_MS}ms"
    failed=1
  fi

  printf '%8s %10s %8s %10s %10s %10s %s\n' "$users" "$reqs" "$fails" "$avg" "$p95" "$rps" "$verdict"

  if [ "$failed" -eq 1 ]; then
    break
  fi
  best="$users"

  sleep "$COOLDOWN"
done

echo ""
if [ -n "$best" ]; then
  echo "[OK] Максимум корректно обслуживаемых пользователей: $best"
  echo "     Повторите прогон на этой ступени с параллельным ./scripts/04-measure.sh,"
  echo "     чтобы снять CPU/RAM в критической точке и вписать новые limits в values."
else
  echo "[WARN] Уже первая ступень не прошла — уменьшите ступени или проверьте кластер."
fi
echo "CSV: $RESULTS_DIR/step-$stamp-u*_stats.csv"
