#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Локальный аналог джобы sonarqube: прогоняет sonar-scanner против SonarQube
# в minikube. Нужен, чтобы проверить анализ, не дожидаясь self-hosted раннера.

ensure_minikube

trap sonar_port_forward_cleanup EXIT

SONAR_TOKEN="$(keychain_get "$KEYCHAIN_TOKEN_SERVICE")" || true
if [ -z "${SONAR_TOKEN:-}" ]; then
  echo "[ERROR] Токен не найден в Keychain ($KEYCHAIN_TOKEN_SERVICE)"
  echo "        Сначала: ./scripts/03-configure-sonarqube.sh"
  exit 1
fi
export SONAR_TOKEN

echo "=== Доступ к SonarQube ==="
sonar_port_forward
sonar_wait_up 600

echo ""
echo "=== Go-покрытие ==="
# Те же профили, что указаны в sonar.go.coverage.reportPaths.
for module in hw1-2 hw-3/go hw-4 hw-7 hw-8 hw-9; do
  [ -f "$REPO_ROOT/$module/go.mod" ] || continue
  echo "--- $module"
  ( cd "$REPO_ROOT/$module" && go test ./... -coverprofile=coverage.out -covermode=atomic ) \
    || echo "[WARN] go test в $module завершился с ошибкой, покрытие может быть неполным"
done

echo ""
echo "=== sonar-scanner ==="
cd "$REPO_ROOT"

if command -v sonar-scanner &>/dev/null; then
  sonar-scanner \
    -Dsonar.host.url="$SONAR_LOCAL_URL"
elif command -v docker &>/dev/null && docker info &>/dev/null; then
  echo "[INFO] sonar-scanner не установлен, использую docker-образ"
  SCM_DISABLED="${SONAR_SCM_DISABLED:-true}"
  if [ "$SCM_DISABLED" = true ]; then
    echo "[INFO] Для локального Docker-прогона отключён сбор Git blame (SCM Publisher)."
    echo "       Полный анализ с Git-атрибуцией: brew install sonar-scanner"
  fi
  # host.docker.internal - как контейнер видит port-forward на хосте.
  docker run --rm \
    -v "$REPO_ROOT:/usr/src" \
    -e SONAR_HOST_URL="http://host.docker.internal:${SONAR_PORT}" \
    -e SONAR_TOKEN \
    sonarsource/sonar-scanner-cli \
    -Dsonar.scm.disabled="$SCM_DISABLED"
else
  echo "[ERROR] Нужен sonar-scanner или запущенный Docker"
  echo "        brew install sonar-scanner"
  exit 1
fi

echo ""
echo "[OK] Анализ отправлен"
echo "[INFO] Результат: http://$SONAR_HOST/dashboard?id=$SONAR_PROJECT_KEY"
echo "[INFO] Через port-forward: ${SONAR_LOCAL_URL}/dashboard?id=$SONAR_PROJECT_KEY"
