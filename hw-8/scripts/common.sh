#!/bin/bash

NAMESPACE="k8s-hw8"
RELEASE="hw8-app"
APP_HOST="hw8.local"
GHCR_USER="fastrapier"
GHCR_REPO="ghcr.io/$GHCR_USER/hw8"
CHART_DIR="helm/app"

# --- Часть 2: свой раннер через Actions Runner Controller ---------------------
GITHUB_REPO="fastrapier/k8s-hw"
GITHUB_REPO_URL="https://github.com/$GITHUB_REPO"

# Версия обоих OCI-чартов ARC пинится: чарт и образ контроллера должны
# совпадать, а «latest» ломает установку при смене CRD.
ARC_CHART_VERSION="0.14.2"
ARC_CONTROLLER_CHART="oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller"
ARC_RUNNER_CHART="oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set"
ARC_SYSTEMS_NS="arc-systems"
ARC_RUNNERS_NS="arc-runners"
ARC_CONTROLLER_RELEASE="arc"
ARC_DIR="arc"

# Имя релиза чарта gha-runner-scale-set = имя scale set = label в `runs-on`.
RUNNER_SCALE_SET="hw8-minikube"
RUNNER_TOKEN_SECRET="hw8-runner-github-token"
RUNNER_SA="hw8-runner-deployer"
RUNNER_CLUSTER_ROLE="hw8-runner-namespace-bootstrap"
# Repo variable, которая включает self-hosted раннер в пайплайне.
RUNNER_VAR="HW8_RUNNER"
ARC_KEYCHAIN_SERVICE="github-arc"

ensure_gh() {
  require_cmd gh "brew install gh"
  if ! gh auth status &>/dev/null; then
    echo "[ERROR] gh не авторизован. Выполните: gh auth login"
    exit 1
  fi
}

# PAT, которым ARC регистрирует раннеры в репозитории. Печатается только в
# stdout функции: в файлы, values и логи токен не попадает.
arc_github_token() {
  local token
  if token=$(security find-generic-password -a "$GHCR_USER" -s "$ARC_KEYCHAIN_SERVICE" -w 2>/dev/null) &&
    [ -n "$token" ]; then
    printf '%s' "$token"
    return 0
  fi

  if command -v gh &>/dev/null && token=$(gh auth token 2>/dev/null) && [ -n "$token" ]; then
    {
      echo "[WARN] PAT для ARC не найден в macOS Keychain — беру токен gh CLI."
      echo "       Это OAuth-токен пользователя: он живёт короче PAT и его scope"
      echo "       меняет 'gh auth refresh'. Для стабильной работы заведите отдельный"
      echo "       classic PAT со scope 'repo' и положите его в Keychain:"
      echo "       security add-generic-password -a $GHCR_USER -s $ARC_KEYCHAIN_SERVICE -w YOUR_PAT -U"
    } >&2
    printf '%s' "$token"
    return 0
  fi

  {
    echo "[ERROR] Нет токена для регистрации раннера."
    echo "        security add-generic-password -a $GHCR_USER -s $ARC_KEYCHAIN_SERVICE -w YOUR_PAT -U"
    echo "        PAT: classic, scope 'repo' (для раннера уровня репозитория)."
  } >&2
  return 1
}

require_cmd() {
  local cmd="$1"
  local install_hint="$2"
  if ! command -v "$cmd" &>/dev/null; then
    echo "[ERROR] $cmd не найден. Установите: $install_hint"
    exit 1
  fi
}

ensure_base() {
  require_cmd minikube "https://minikube.sigs.k8s.io/docs/start/"
  require_cmd kubectl  "brew install kubectl"
  require_cmd helm     "brew install helm"
}

ensure_minikube() {
  ensure_base
  local profile
  profile="${MINIKUBE_PROFILE:-$(minikube profile)}"
  profile="${profile#\* }"
  if ! minikube -p "$profile" status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    echo "[ERROR] Minikube '$profile' не запущен. Запустите: minikube start -p $profile"
    exit 1
  fi
  if ! kubectl config use-context "$profile" >/dev/null; then
    echo "[ERROR] В kubeconfig нет контекста '$profile'. Проверьте KUBECONFIG." >&2
    return 1
  fi
}

ensure_node() {
  require_cmd node "brew install node"
  require_cmd npm  "brew install node"
}

add_host() {
  local host="$1"
  if grep -q "$host" /etc/hosts; then
    sudo sed -i '' "/$host/d" /etc/hosts
  fi
  echo "127.0.0.1 $host" | sudo tee -a /etc/hosts >/dev/null
  echo "[OK] $host -> 127.0.0.1"
}

add_helm_repo() {
  local name="$1"
  local url="$2"
  if ! helm repo list 2>/dev/null | grep -q "^${name}"; then
    helm repo add "$name" "$url"
    helm repo update
    echo "[OK] Helm repo $name добавлен"
  else
    echo "[INFO] Helm repo $name уже существует"
  fi
}

helm_cleanup_pending() {
  local release="$1"
  local status
  status=$(helm status "$release" -n "$NAMESPACE" -o json 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4) || true
  if [[ "$status" == pending-* ]]; then
    echo "[WARN] Релиз $release завис в состоянии $status, очищаю..."
    helm uninstall "$release" -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete secret -n "$NAMESPACE" -l "owner=helm,name=$release" 2>/dev/null || true
  fi
}

ensure_namespace() {
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

create_ghcr_pull_secret() {
  local token
  token=$(security find-generic-password -a "$GHCR_USER" -s ghcr.io -w 2>/dev/null) || {
    echo "[WARN] Токен ghcr.io не найден в macOS Keychain — imagePullSecret не создан."
    echo "       Для приватного пакета сохраните токен:"
    echo "       security add-generic-password -a $GHCR_USER -s ghcr.io -w YOUR_GITHUB_TOKEN -U"
    return 1
  }

  kubectl create secret docker-registry ghcr-pull-secret \
    -n "$NAMESPACE" \
    --docker-server=ghcr.io \
    --docker-username="$GHCR_USER" \
    --docker-password="$token" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "[OK] K8s imagePullSecret ghcr-pull-secret создан"
}

# Тег образа = версия из semantic-release без префикса "v".
# Приоритет: аргумент → последний git-тег → latest.
resolve_tag() {
  local tag="${1:-}"
  if [ -z "$tag" ]; then
    tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
  fi
  if [ -z "$tag" ]; then
    tag="latest"
  fi
  echo "${tag#v}"
}
