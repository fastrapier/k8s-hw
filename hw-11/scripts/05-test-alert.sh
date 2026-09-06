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
echo "=== Тестовое уведомление на contact point ==="
# Эндпоинт есть в Grafana 12.x (наш чарт ставит 12.3.1) и удалён в Grafana 13,
# где вместо него /apis/notifications.alerting.grafana.app/.../receivers/{uid}/test.
TEST_BODY="$(curl -fsS --max-time 15 -u "$AUTH" "$BASE/api/v1/provisioning/contact-points" \
  | python3 "$RENDER" grafana-test-body email-hw11)" || {
  echo "[ERROR] Не удалось собрать тело запроса — контакт email-hw11 не найден"
  exit 1
}

TEST_OUT="$(mktemp)"
TEST_CODE="$(curl -s -o "$TEST_OUT" -w '%{http_code}' --max-time 30 -u "$AUTH" \
  -H 'Content-Type: application/json' -X POST \
  "$BASE/api/alertmanager/grafana/config/api/v1/receivers/test" \
  -d "$TEST_BODY")"
echo "  HTTP $TEST_CODE"
python3 -m json.tool < "$TEST_OUT" 2>/dev/null || cat "$TEST_OUT"
echo ""
rm -f "$TEST_OUT"

case "$TEST_CODE" in
  200)
    echo "[OK] Тестовое письмо отправлено на $ALERT_EMAIL"
    ;;
  410)
    echo "[WARN] Эндпоинт удалён — это Grafana 13+."
    echo "       Используйте новый API или кнопку Test в UI:"
    echo "       http://$GRAFANA_HOST/alerting/notifications"
    ;;
  *)
    echo "[WARN] Тестовое письмо не отправлено (HTTP $TEST_CODE)."
    echo "       Проверьте SMTP-настройки и логи Grafana ниже."
    ;;
esac

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
