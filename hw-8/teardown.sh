#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"
source "$SCRIPT_DIR/common.sh"

echo "=== Отключение self-hosted раннера от пайплайна ==="
# Сначала переменная, потом раннер: иначе новые джобы уйдут в очередь к
# раннеру, которого уже нет, и будут висеть до таймаута GitHub.
if command -v gh &>/dev/null; then
  gh variable delete "$RUNNER_VAR" --repo "$GITHUB_REPO" 2>/dev/null &&
    echo "[OK] Repo variable $RUNNER_VAR удалена" ||
    echo "[INFO] Repo variable $RUNNER_VAR не найдена"
else
  echo "[WARN] gh не найден — удалите переменную $RUNNER_VAR вручную"
fi

echo "=== Удаление scale set $RUNNER_SCALE_SET ==="
# Порядок обязателен: finalizer'ы AutoscalingRunnerSet снимает контроллер,
# поэтому scale set удаляется ДО контроллера — иначе uninstall зависнет.
helm uninstall "$RUNNER_SCALE_SET" -n "$ARC_RUNNERS_NS" --wait --timeout=5m 2>/dev/null &&
  echo "[OK] scale set удалён" || echo "[INFO] scale set не найден"

echo "=== Удаление контроллера ARC ==="
helm uninstall "$ARC_CONTROLLER_RELEASE" -n "$ARC_SYSTEMS_NS" --wait --timeout=5m 2>/dev/null &&
  echo "[OK] контроллер удалён" || echo "[INFO] контроллер не найден"

echo "=== Удаление RBAC и секрета раннера ==="
kubectl delete -f "$(dirname "$SCRIPT_DIR")/$ARC_DIR/deployer-rbac.yaml" --ignore-not-found
kubectl delete secret "$RUNNER_TOKEN_SECRET" -n "$ARC_RUNNERS_NS" --ignore-not-found
kubectl delete namespace "$ARC_RUNNERS_NS" "$ARC_SYSTEMS_NS" --ignore-not-found

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
echo "     CRD ARC helm не удаляет (так задумано в чарте). Если нужно:"
echo "     kubectl get crd -o name | grep actions.github.com | xargs kubectl delete"
echo "     Git-теги и GitHub Releases скриптом НЕ удаляются: ими управляет semantic-release."
