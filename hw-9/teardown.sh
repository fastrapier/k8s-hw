#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

echo "=== Удаление werf-релиза ==="
cd "$PROJECT_ROOT"
werf dismiss --release "$RELEASE" --namespace "$NAMESPACE" 2>/dev/null \
  && echo "[OK] release $RELEASE удалён" \
  || echo "[INFO] release $RELEASE не найден"

echo "=== Очистка оставшихся ресурсов ==="
# Job миграций создаётся helm-хуком и в релиз не входит, поэтому удаляется руками
kubectl delete job backend-migrations -n "$NAMESPACE" --ignore-not-found
kubectl delete secret "$PULL_SECRET" -n "$NAMESPACE" --ignore-not-found
# PVC backend помечен helm.sh/resource-policy: keep — dismiss его не тронет
kubectl delete pvc backend-data -n "$NAMESPACE" --ignore-not-found
kubectl delete pvc data-postgres-0 -n "$NAMESPACE" --ignore-not-found

echo "=== Удаление Vault ==="
helm uninstall vault -n "$NAMESPACE" 2>/dev/null && echo "[OK] Vault удалён" || echo "[INFO] Vault не найден"
kubectl delete pvc -n "$NAMESPACE" -l app.kubernetes.io/name=vault --ignore-not-found

echo "=== Локальные файлы ==="
rm -f "$PROJECT_ROOT/secret-values.rendered.yaml"

echo "=== Очистка /etc/hosts ==="
for h in "$VAULT_HOST" "$APP_HOST"; do
  if grep -q "$h" /etc/hosts 2>/dev/null; then
    sudo sed -i '' "/$h/d" /etc/hosts
    echo "[OK] $h удалён из /etc/hosts"
  fi
done

echo ""
echo "[OK] Всё очищено. Namespace $NAMESPACE остался."
echo "     Для полного удаления: kubectl delete namespace $NAMESPACE"
