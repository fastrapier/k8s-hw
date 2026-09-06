#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_gh
cd "$PROJECT_ROOT"

echo "=== Self-hosted раннер: ARC $ARC_CHART_VERSION, scale set $RUNNER_SCALE_SET ==="

echo "--- Namespaces ---"
for ns in "$ARC_SYSTEMS_NS" "$ARC_RUNNERS_NS" "$NAMESPACE"; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo "--- Контроллер ARC в $ARC_SYSTEMS_NS ---"
helm upgrade --install "$ARC_CONTROLLER_RELEASE" "$ARC_CONTROLLER_CHART" \
  --version "$ARC_CHART_VERSION" \
  --namespace "$ARC_SYSTEMS_NS" \
  --wait --timeout=5m

echo "--- Секрет с токеном GitHub в $ARC_RUNNERS_NS ---"
TOKEN=$(arc_github_token)
kubectl create secret generic "$RUNNER_TOKEN_SECRET" \
  --namespace "$ARC_RUNNERS_NS" \
  --from-literal=github_token="$TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
unset TOKEN
echo "[OK] Секрет $RUNNER_TOKEN_SECRET создан"

echo "--- RBAC: раннеру право на helm upgrade в $NAMESPACE ---"
kubectl apply -f "$ARC_DIR/deployer-rbac.yaml"

# Приватный пакет в GHCR: без секрета под приложения не стянет образ.
create_ghcr_pull_secret || true

echo "--- Scale set $RUNNER_SCALE_SET в $ARC_RUNNERS_NS ---"
helm upgrade --install "$RUNNER_SCALE_SET" "$ARC_RUNNER_CHART" \
  --version "$ARC_CHART_VERSION" \
  --namespace "$ARC_RUNNERS_NS" \
  --values "$ARC_DIR/runner-values.yaml" \
  --wait --timeout=5m

echo "--- Ожидание готовности ---"
# helm --wait ждёт только AutoscalingRunnerSet; listener и под раннера
# создаёт контроллер уже после того, как helm вернул управление.
deadline=$((SECONDS + 240))
runner_ready=false
while [ "$SECONDS" -lt "$deadline" ]; do
  if kubectl get pods -n "$ARC_RUNNERS_NS" \
    --field-selector=status.phase=Running -o name 2>/dev/null | grep -q .; then
    runner_ready=true
    break
  fi
  sleep 5
done

kubectl get autoscalingrunnersets -n "$ARC_RUNNERS_NS"
kubectl get pods -n "$ARC_SYSTEMS_NS"
kubectl get pods -n "$ARC_RUNNERS_NS"

if [ "$runner_ready" != true ]; then
  echo "[ERROR] Под раннера не поднялся за 240с. Логи контроллера и listener:"
  echo "  kubectl logs -n $ARC_SYSTEMS_NS -l app.kubernetes.io/part-of=gha-rs-controller --tail=50"
  echo "  kubectl logs -n $ARC_SYSTEMS_NS -l app.kubernetes.io/component=runner-scale-set-listener --tail=50"
  exit 1
fi

echo "--- Регистрация в GitHub ---"
if ! gh api "repos/$GITHUB_REPO/actions/runners" \
  --jq '.runners[] | "\(.name)  status=\(.status)  labels=\([.labels[].name] | join(","))"'; then
  echo "[WARN] Не удалось прочитать список раннеров через API (нужен scope 'repo')."
  echo "       Проверьте вручную: $GITHUB_REPO_URL/settings/actions/runners"
fi

echo "--- Включение раннера в пайплайне ---"
# Пока переменной нет, джоба deploy остаётся на ubuntu-latest: иначе при
# выключенном minikube она висела бы в очереди до таймаута GitHub.
gh variable set "$RUNNER_VAR" --body "$RUNNER_SCALE_SET" --repo "$GITHUB_REPO"
echo "[OK] Repo variable $RUNNER_VAR=$RUNNER_SCALE_SET"

echo ""
echo "[OK] Раннер подключён. Запуск пайплайна на нём:"
echo "  gh workflow run hw8-release.yml --repo $GITHUB_REPO -f tag=\$(git describe --tags --abbrev=0 | tr -d v)"
echo "  gh run watch --repo $GITHUB_REPO"
