#!/bin/bash
# Разбор строки Aggregated из locust *_stats.csv.
#
# Без аргументов печатает человекочитаемую сводку; с --tsv отдаёт
# "reqs<TAB>fails<TAB>avg_ms<TAB>p95_ms<TAB>rps" для использования в скриптах.
#
# Колонки locust 2.x: 1 Type, 2 Name, 3 Request Count, 4 Failure Count,
# 5 Median, 6 Average Response Time, 7 Min, 8 Max, 9 Avg Content Size,
# 10 Requests/s, 11 Failures/s, 12 50% ... 17 95%.
set -euo pipefail

csv="${1:-}"
mode="${2:-human}"

if [ -z "$csv" ] || [ ! -f "$csv" ]; then
  echo "[ERROR] нет файла со статистикой: ${csv:-<не задан>}" >&2
  exit 1
fi

read -r reqs fails avg p95 rps <<< "$(
  awk -F, '$2 == "Aggregated" { printf "%d %d %.0f %.0f %.1f", $3, $4, $6, $17, $10 }' "$csv"
)"

if [ -z "${reqs:-}" ]; then
  echo "[ERROR] в $csv нет строки Aggregated" >&2
  exit 1
fi

if [ "$mode" = "--tsv" ]; then
  printf '%s\t%s\t%s\t%s\t%s\n' "$reqs" "$fails" "$avg" "$p95" "$rps"
  exit 0
fi

printf 'запросов:      %s\n' "$reqs"
printf 'ошибок:        %s\n' "$fails"
printf 'avg:           %s ms\n' "$avg"
printf 'p95:           %s ms\n' "$p95"
printf 'RPS:           %s\n' "$rps"
