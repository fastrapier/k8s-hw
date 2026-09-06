#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

RENDER="$SCRIPT_DIR/lib/render.py"
trap port_forward_cleanup EXIT

ensure_minikube
load_env

BASE="$(grafana_base_url)"
AUTH="admin:$GRAFANA_ADMIN_PASSWORD"
echo "[INFO] Grafana API: $BASE"

echo ""
echo "=== Контакты (provisioned) ==="
curl -fsS --max-time 15 -u "$AUTH" "$BASE/api/v1/provisioning/contact-points" \
  | python3 "$RENDER" grafana-contact-points

echo ""
echo "=== Правила алертинга (provisioned) ==="
curl -fsS --max-time 15 -u "$AUTH" "$BASE/api/prometheus/grafana/api/v1/rules" \
  | python3 "$RENDER" grafana-rules

echo ""
echo "=== Проверка SMTP ==="
# Grafana не отдаёт статус SMTP отдельным эндпоинтом: если конфиг битый,
# ошибка появляется в логах при первой попытке отправки.
kubectl logs deployment/grafana -n "$NAMESPACE" -c grafana --tail=200 2>/dev/null \
  | grep -iE 'smtp|failed to send' | tail -5 || echo "  упоминаний SMTP в логах пока нет"

echo ""
echo "=== Провоцируем реальный алерт ==="
echo "[INFO] Правило hw11-ingress-rps срабатывает при RPS > 1 в течение 1 минуты."
echo "[INFO] Гоняю запросы через ingress ~150 секунд, затем смотрю состояние правила."

END=$((SECONDS + 150))
while [ "$SECONDS" -lt "$END" ]; do
  for _ in $(seq 1 10); do
    curl -fsS --max-time 2 "http://$PROMETHEUS_HOST/-/ready" &>/dev/null || true
  done
  sleep 1
done
echo "[OK] Нагрузка отправлена"

echo ""
echo "=== Состояние правил после нагрузки ==="
for attempt in 1 2 3 4 5 6; do
  echo "--- попытка $attempt"
  curl -fsS --max-time 15 -u "$AUTH" "$BASE/api/prometheus/grafana/api/v1/rules" \
    | python3 "$RENDER" grafana-rules
  if curl -fsS --max-time 15 -u "$AUTH" "$BASE/api/prometheus/grafana/api/v1/rules" \
    | grep -q '"state":"firing"'; then
    echo "[OK] Правило в состоянии firing — письмо уходит на $ALERT_EMAIL"
    break
  fi
  sleep 30
done

echo ""
echo "[INFO] Если письма нет:"
echo "  1. Проверьте папку «Спам»."
echo "  2. Логи Grafana: kubectl logs deployment/grafana -n $NAMESPACE -c grafana | grep -i smtp"
echo "  3. Отправьте тестовое письмо кнопкой в UI:"
echo "     http://$GRAFANA_HOST/alerting/notifications -> email-hw11 -> Edit -> Test"
echo "     (HTTP-эндпоинт для теста контакта в Grafana 12 удалён, см. README.MD)"
