#!/bin/bash

NAMESPACE="k8s-hw8"
RELEASE="hw8-app"
APP_HOST="hw8.local"
GHCR_USER="fastrapier"
GHCR_REPO="ghcr.io/$GHCR_USER/hw8"
CHART_DIR="helm/app"

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
