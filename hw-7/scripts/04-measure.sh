#!/bin/bash
# ЧАСТЬ 1 и 2 — исследование потребления CPU и RAM подами API.
#
# Снимает kubectl top несколько раз и печатает min/avg/max по каждому поду
# и суммарно. Используется и в покое, и во время нагрузки (запускать
# параллельно с 05-locust-local.sh во втором терминале).
#
#   SAMPLES=20 INTERVAL=5 ./scripts/04-measure.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SAMPLES="${SAMPLES:-12}"
INTERVAL="${INTERVAL:-5}"
SELECTOR="${SELECTOR:-$API_SELECTOR}"

ensure_minikube

echo "=== Замер потребления: $SAMPLES проб с интервалом ${INTERVAL}s (selector: $SELECTOR) ==="
echo ""

raw=$(mktemp)
trap 'rm -f "$raw"' EXIT

for ((i = 1; i <= SAMPLES; i++)); do
  ts=$(date +%H:%M:%S)
  # kubectl top отдаёт "NAME CPU(cores) MEMORY(bytes)" вида "api-xxx 12m 34Mi"
  if out=$(kubectl top pods -n "$NAMESPACE" -l "$SELECTOR" --no-headers 2>/dev/null); then
    pods=$(echo "$out" | grep -c . || true)
    while read -r name cpu mem; do
      [ -z "${name:-}" ] && continue
      printf '%s\t%s\t%s\t%s\n' "$ts" "$name" "${cpu%m}" "${mem%Mi}" >> "$raw"
    done <<< "$out"
    printf '[%s] проба %2d/%d, подов: %s\n' "$ts" "$i" "$SAMPLES" "${pods:-0}"
    echo "$out" | sed 's/^/    /'
  else
    printf '[%s] проба %2d/%d: метрик нет (metrics-server не готов?)\n' "$ts" "$i" "$SAMPLES"
  fi
  (( i < SAMPLES )) && sleep "$INTERVAL"
done

echo ""
echo "=== Итог по подам ==="
if [ ! -s "$raw" ]; then
  echo "[WARN] проб не собрано"
  exit 0
fi

awk -F'\t' '
  {
    n[$2]++
    cpu_sum[$2] += $3; mem_sum[$2] += $4
    if (!($2 in cpu_max) || $3 > cpu_max[$2]) cpu_max[$2] = $3
    if (!($2 in mem_max) || $4 > mem_max[$2]) mem_max[$2] = $4
    if (!($2 in cpu_min) || $3 < cpu_min[$2]) cpu_min[$2] = $3
    if (!($2 in mem_min) || $4 < mem_min[$2]) mem_min[$2] = $4
    tot_cpu += $3; tot_mem += $4; tot_n++
  }
  END {
    printf "%-40s %6s %8s %8s %8s %8s %8s %8s\n", "POD", "N", "CPUmin", "CPUavg", "CPUmax", "MEMmin", "MEMavg", "MEMmax"
    for (p in n)
      printf "%-40s %6d %7dm %7dm %7dm %7dMi %6dMi %6dMi\n", p, n[p],
             cpu_min[p], cpu_sum[p]/n[p], cpu_max[p],
             mem_min[p], mem_sum[p]/n[p], mem_max[p]
    if (tot_n > 0)
      printf "\nСреднее на под по всем пробам: CPU %dm, RAM %dMi\n", tot_cpu/tot_n, tot_mem/tot_n
  }
' "$raw"

echo ""
echo "Эти цифры идут в таблицу «Результаты исследования» в README.MD."
