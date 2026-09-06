#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"
source "$SCRIPT_DIR/common.sh"

echo "=== Удаление Helm-релиза $RELEASE ==="
helm uninstall "$RELEASE" -n "$NAMESPACE" 2>/dev/null && echo "[OK] release удалён" || echo "[INFO] release не найден"

echo "=== Очистка оставшихся ресурсов ==="
kubectl delete deployment "$RELEASE" -n "$NAMESPACE" --ignore-not-found
kubectl delete service "$RELEASE" -n "$NAMESPACE" --ignore-not-found
kubectl delete ingress "$RELEASE" -n "$NAMESPACE" --ignore-not-found

echo "=== Удаление K8s Secrets ==="
kubectl delete secret ghcr-pull-secret -n "$NAMESPACE" --ignore-not-found

echo "=== Очистка /etc/hosts ==="
if grep -q "$APP_HOST" /etc/hosts 2>/dev/null; then
  sudo sed -i '' "/$APP_HOST/d" /etc/hosts
  echo "[OK] $APP_HOST удалён из /etc/hosts"
fi

echo "=== Локальные артефакты ==="
rm -f "$(dirname "$SCRIPT_DIR")/.version"

echo ""
echo "[OK] Всё очищено. Namespace $NAMESPACE остался."
echo "     Для полного удаления: kubectl delete namespace $NAMESPACE"
echo "     Git-теги и GitHub Releases скриптом НЕ удаляются: ими управляет semantic-release."
