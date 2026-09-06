#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SET_SECRETS=false
if [ "${1:-}" = "--set-secrets" ]; then
  SET_SECRETS=true
fi

ensure_minikube
require_cmd curl "входит в macOS"

trap sonar_port_forward_cleanup EXIT

echo "=== Доступ к SonarQube ==="
sonar_port_forward
sonar_wait_up 900

ADMIN_PASSWORD="$(keychain_get_or_create "$KEYCHAIN_PASSWORD_SERVICE")"

echo ""
echo "=== Пароль администратора ==="
# Идемпотентность: если пароль уже сменён прошлым запуском, смена с
# previousPassword=admin вернёт 401 - тогда проверяем, что рабочий пароль
# из Keychain действительно подходит, и идём дальше.
change_code=$(curl -s -o /tmp/sonar-chpwd.out -w '%{http_code}' \
  -u "admin:admin" \
  -X POST "${SONAR_LOCAL_URL}/api/users/change_password" \
  --data-urlencode "login=admin" \
  --data-urlencode "previousPassword=admin" \
  --data-urlencode "password=${ADMIN_PASSWORD}") || true

if [ "$change_code" = "204" ] || [ "$change_code" = "200" ]; then
  echo "[OK] Пароль admin сменён, значение в Keychain ($KEYCHAIN_PASSWORD_SERVICE)"
else
  auth_code=$(curl -s -o /dev/null -w '%{http_code}' \
    -u "admin:${ADMIN_PASSWORD}" \
    "${SONAR_LOCAL_URL}/api/authentication/validate?format=json") || true
  if [ "$auth_code" = "200" ]; then
    echo "[INFO] Пароль уже сменён ранее, текущий пароль из Keychain подходит"
  else
    echo "[ERROR] Не удалось ни сменить пароль (код $change_code), ни авторизоваться сохранённым (код $auth_code)"
    echo "        Сбросить: удалите Keychain-запись ($KEYCHAIN_PASSWORD_SERVICE) и переустановите релиз"
    cat /tmp/sonar-chpwd.out 2>/dev/null || true
    exit 1
  fi
fi
rm -f /tmp/sonar-chpwd.out

CURL_AUTH=(-u "admin:${ADMIN_PASSWORD}")

echo ""
echo "=== Проект $SONAR_PROJECT_KEY ==="
create_code=$(curl -s -o /tmp/sonar-project.out -w '%{http_code}' \
  "${CURL_AUTH[@]}" \
  -X POST "${SONAR_LOCAL_URL}/api/projects/create" \
  --data-urlencode "project=${SONAR_PROJECT_KEY}" \
  --data-urlencode "name=Kubernetes homeworks") || true

if [ "$create_code" = "200" ]; then
  echo "[OK] Проект $SONAR_PROJECT_KEY создан"
elif grep -q "key already exists" /tmp/sonar-project.out 2>/dev/null; then
  echo "[INFO] Проект $SONAR_PROJECT_KEY уже существует"
else
  echo "[ERROR] Не удалось создать проект (код $create_code)"
  cat /tmp/sonar-project.out 2>/dev/null || true
  exit 1
fi
rm -f /tmp/sonar-project.out

echo ""
echo "=== Токен $SONAR_TOKEN_NAME ==="
# Токен показывается ровно один раз при генерации, поэтому старый отзываем
# и генерируем заново - иначе повторный запуск не смог бы его отдать.
curl -s -o /dev/null "${CURL_AUTH[@]}" \
  -X POST "${SONAR_LOCAL_URL}/api/user_tokens/revoke" \
  --data-urlencode "name=${SONAR_TOKEN_NAME}" || true

SONAR_TOKEN=$(curl -s "${CURL_AUTH[@]}" \
  -X POST "${SONAR_LOCAL_URL}/api/user_tokens/generate" \
  --data-urlencode "name=${SONAR_TOKEN_NAME}" \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

if [ -z "$SONAR_TOKEN" ]; then
  echo "[ERROR] Не удалось сгенерировать токен"
  exit 1
fi

keychain_set "$KEYCHAIN_TOKEN_SERVICE" "$SONAR_TOKEN"

echo ""
echo "============================================================"
echo "[OK] SonarQube настроен"
echo "  UI:      http://$SONAR_HOST  (или $SONAR_LOCAL_URL через port-forward)"
echo "  Логин:   admin"
echo "  Пароль:  security find-generic-password -a $KEYCHAIN_ACCOUNT -s $KEYCHAIN_PASSWORD_SERVICE -w"
echo "  Токен:   security find-generic-password -a $KEYCHAIN_ACCOUNT -s $KEYCHAIN_TOKEN_SERVICE -w"
echo "============================================================"
echo ""

if [ "$SET_SECRETS" = true ]; then
  require_cmd gh "brew install gh"
  echo "=== Установка секретов репозитория ==="
  printf '%s' "$SONAR_TOKEN" | gh secret set SONAR_TOKEN
  printf '%s' "$SONAR_IN_CLUSTER_URL" | gh secret set SONAR_HOST_URL
  echo "[OK] SONAR_TOKEN и SONAR_HOST_URL установлены"
  echo "[WARN] SONAR_HOST_URL = $SONAR_IN_CLUSTER_URL - этот адрес виден только"
  echo "       self-hosted раннеру внутри кластера (ДЗ 8, часть 2)."
else
  echo "Дальше - руками (скрипт сознательно не трогает секреты репозитория):"
  echo ""
  echo "  # 1. Вариант для self-hosted раннера в кластере (ДЗ 8, часть 2):"
  echo "  gh secret set SONAR_HOST_URL --body '$SONAR_IN_CLUSTER_URL'"
  echo ""
  echo "  # 2. Вариант, когда SonarQube доступен снаружи по своему адресу:"
  echo "  gh secret set SONAR_HOST_URL --body 'https://sonarqube.example.com'"
  echo ""
  echo "  # Токен:"
  echo "  security find-generic-password -a $KEYCHAIN_ACCOUNT -s $KEYCHAIN_TOKEN_SERVICE -w | gh secret set SONAR_TOKEN"
  echo ""
  echo "  Или разом: $0 --set-secrets"
fi
