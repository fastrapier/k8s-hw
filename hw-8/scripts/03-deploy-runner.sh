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
ready_timeout="${ARC_READY_TIMEOUT:-600}"
if ! [[ "$ready_timeout" =~ ^[1-9][0-9]*$ ]]; then
  echo "[ERROR] ARC_READY_TIMEOUT должен быть положительным числом секунд." >&2
  exit 1
fi
wait_started=$SECONDS
deadline=$((SECONDS + ready_timeout))
runner_ready=false
while [ "$SECONDS" -lt "$deadline" ]; do
  # После первого reconcile отсутствующий ERS означает сломанную ссылку
  # listener; перезапуск его пода эту ссылку не исправляет.
  if [ $((SECONDS - wait_started)) -ge 30 ]; then
    listener_refs=$(kubectl get autoscalinglisteners -n "$ARC_SYSTEMS_NS" \
      -l "actions.github.com/scale-set-name=$RUNNER_SCALE_SET,actions.github.com/scale-set-namespace=$ARC_RUNNERS_NS" \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.ephemeralRunnerSetName}{"\n"}{end}')
    while read -r listener_name runner_set; do
      [ -n "$listener_name" ] && [ -n "$runner_set" ] || continue
      existing_set=$(kubectl get ephemeralrunnerset "$runner_set" -n "$ARC_RUNNERS_NS" \
        --ignore-not-found -o name)
      if [ -z "$existing_set" ]; then
        echo "[ERROR] Listener $listener_name ссылается на отсутствующий EphemeralRunnerSet $runner_set."
        echo "        Пересоздайте объект listener и повторите скрипт:"
        echo "  kubectl delete autoscalinglisteners.actions.github.com $listener_name -n $ARC_SYSTEMS_NS"
        exit 1
      fi
    done <<< "$listener_refs"
  fi

  if kubectl get pods -n "$ARC_RUNNERS_NS" \
    -l "actions.github.com/scale-set-name=$RUNNER_SCALE_SET" \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -q '^True$'; then
    online_runners=$(gh api "repos/$GITHUB_REPO/actions/runners" \
      --paginate --jq '.runners[] | select(.status == "online") | .name')
    if printf '%s\n' "$online_runners" | grep -q "^${RUNNER_SCALE_SET}-"; then
      runner_ready=true
      break
    fi
  fi
  sleep 5
done

kubectl get autoscalingrunnersets -n "$ARC_RUNNERS_NS"
kubectl get pods -n "$ARC_SYSTEMS_NS"
kubectl get pods -n "$ARC_RUNNERS_NS"

if [ "$runner_ready" != true ]; then
  echo "[ERROR] Раннер не достиг Ready и online в GitHub за ${ready_timeout}с."
  kubectl get events -n "$ARC_RUNNERS_NS" --sort-by=.lastTimestamp
  echo "Логи контроллера и listener:"
  echo "  kubectl logs -n $ARC_SYSTEMS_NS -l app.kubernetes.io/part-of=gha-rs-controller --tail=50"
  echo "  kubectl logs -n $ARC_SYSTEMS_NS -l app.kubernetes.io/component=runner-scale-set-listener --tail=50"
  exit 1
fi

echo "--- Регистрация в GitHub ---"
if ! gh api "repos/$GITHUB_REPO/actions/runners" \
      --paginate --jq '.runners[] | "\(.name)  status=\(.status)  labels=\([.labels[].name] | join(","))"'; then
  echo "[WARN] Не удалось прочитать список раннеров через API (нужен scope 'repo')."
  echo "       Проверьте вручную: $GITHUB_REPO_URL/settings/actions/runners"
fi

echo "--- Включение раннера в пайплайне ---"
# Пока переменной нет, джоба deploy остаётся на ubuntu-latest: иначе при
# выключенном minikube она висела бы в очереди до таймаута GitHub.
gh variable set "$RUNNER_VAR" --body "$RUNNER_SCALE_SET" --repo "$GITHUB_REPO"
echo "[OK] Repo variable $RUNNER_VAR=$RUNNER_SCALE_SET"

echo ""
demo_tag="${DEMO_TAG:-$(resolve_tag)}"
echo "[OK] Раннер подключён. После слияния workflow в main запуск по готовому тегу:"
echo "  gh workflow run hw8-release.yml --repo $GITHUB_REPO -f tag=$demo_tag"
echo "  gh run watch --repo $GITHUB_REPO"
