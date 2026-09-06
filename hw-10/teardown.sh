#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"
source "$SCRIPT_DIR/common.sh"

echo "=== Удаление SonarQube ==="
helm uninstall "$SONAR_RELEASE" -n "$NAMESPACE" 2>/dev/null \
  && echo "[OK] SonarQube удалён" \
  || echo "[INFO] SonarQube не найден"

echo ""
echo "=== Удаление PVC ==="
# helm uninstall не удаляет PVC от StatefulSet - иначе данные копились бы молча.
kubectl delete pvc -n "$NAMESPACE" -l app=sonarqube --ignore-not-found
kubectl delete pvc "$SONAR_SVC" -n "$NAMESPACE" --ignore-not-found

echo ""
echo "=== Удаление тестового пода чарта ==="
kubectl delete pod sonarqube-ui-test -n "$NAMESPACE" --ignore-not-found

echo ""
echo "=== Очистка /etc/hosts ==="
if grep -q "$SONAR_HOST" /etc/hosts 2>/dev/null; then
  sudo sed -i '' "/$SONAR_HOST/d" /etc/hosts
  echo "[OK] $SONAR_HOST удалён из /etc/hosts"
else
  echo "[INFO] $SONAR_HOST в /etc/hosts не найден"
fi

echo ""
echo "=== Отключение хуков pre-commit ==="
if command -v pre-commit &>/dev/null; then
  cd "$REPO_ROOT"
  pre-commit uninstall || true
else
  echo "[INFO] pre-commit не установлен"
fi

echo ""
echo "=== Секреты в Keychain ==="
# Не удаляем молча: пароль и токен могут быть ещё нужны (например, секреты
# репозитория ещё живы). Печатаем команды, решение - за человеком.
echo "[INFO] Записи оставлены. Удалить вручную:"
for service in "$KEYCHAIN_PASSWORD_SERVICE" "$KEYCHAIN_PASSCODE_SERVICE" "$KEYCHAIN_TOKEN_SERVICE"; do
  echo "  security delete-generic-password -a $KEYCHAIN_ACCOUNT -s $service"
done

echo ""
echo "[OK] Всё очищено. Namespace $NAMESPACE остался."
echo "     Для полного удаления: kubectl delete namespace $NAMESPACE"
echo ""
echo "[INFO] Секреты репозитория (SONAR_TOKEN, SONAR_HOST_URL) не тронуты."
echo "       Удалить: gh secret delete SONAR_TOKEN && gh secret delete SONAR_HOST_URL"
