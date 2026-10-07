#!/bin/bash

NAMESPACE="k8s-hw7"
API_HOST="api-hw7.local"
LOCUST_HOST="locust-hw7.local"
GHCR_USER="fastrapier"
GHCR_REPO="ghcr.io/$GHCR_USER/hw7"

API_SELECTOR="app.kubernetes.io/name=api"
API_DEPLOYMENT="api"

VPA_RELEASE="vpa"
VPA_REPO_NAME="fairwinds-stable"
VPA_REPO_URL="https://charts.fairwinds.com/stable"
VPA_CHART="fairwinds-stable/vpa"
VPA_CHART_VERSION="5.0.1"

LOCUST_OPERATOR_RELEASE="locust-operator"
LOCUST_OPERATOR_REPO_NAME="locust-k8s-operator"
LOCUST_OPERATOR_REPO_URL="https://abdelrhmanhamouda.github.io/locust-k8s-operator/"
LOCUST_OPERATOR_CHART="locust-k8s-operator/locust-k8s-operator"
LOCUST_OPERATOR_CHART_VERSION="2.3.1"
LOCUST_RELEASE="locust"
LOCUST_TEST_NAME="load-test-v2"

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
  if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    echo "[ERROR] Minikube не запущен. Запустите: minikube start"
    exit 1
  fi

  local profile
  profile="${MINIKUBE_PROFILE:-$(minikube profile)}"
  # Некоторые версии minikube помечают активный профиль как "* имя".
  profile="${profile#\* }"
  if kubectl config use-context "$profile" >/dev/null 2>&1; then
    return 0
  fi

  if [ "$(kubectl config current-context 2>/dev/null)" = "minikube" ] &&
     [ "$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null)" = "$profile" ]; then
    return 0
  fi

  echo "[ERROR] В kubeconfig нет контекста для профиля Minikube '$profile'." >&2
  echo "        Проверьте KUBECONFIG и выполните: kubectl config use-context $profile" >&2
  return 1
}

ensure_werf() {
  require_cmd werf "curl -sSL https://werf.io/install.sh | bash"
}

ensure_locust() {
  require_cmd locust "brew install locust (или pip3 install --user locust)"
}

ensure_namespace() {
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "[OK] namespace $NAMESPACE"
}

add_host() {
  local host="$1"
  if grep -q "$host" /etc/hosts; then
    sudo sed -i '' "/$host/d" /etc/hosts
  fi
  echo "127.0.0.1 $host" | sudo tee -a /etc/hosts >/dev/null
  echo "[OK] $host -> 127.0.0.1"
}

remove_host() {
  local host="$1"
  if grep -q "$host" /etc/hosts 2>/dev/null; then
    sudo sed -i '' "/$host/d" /etc/hosts
    echo "[OK] $host удалён из /etc/hosts"
  fi
}

ensure_ghcr_login() {
  if docker login ghcr.io --get-login &>/dev/null 2>&1; then
    echo "[INFO] ghcr.io уже авторизован"
    return
  fi

  local token
  token=$(security find-generic-password -a "$GHCR_USER" -s ghcr.io -w 2>/dev/null) || {
    echo "[ERROR] Токен ghcr.io не найден в macOS Keychain"
    echo "  Сохраните: security add-generic-password -a $GHCR_USER -s ghcr.io -w YOUR_GITHUB_TOKEN -U"
    exit 1
  }

  echo "$token" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
  echo "[OK] ghcr.io авторизован через Keychain"
}

create_ghcr_pull_secret() {
  local token
  token=$(security find-generic-password -a "$GHCR_USER" -s ghcr.io -w 2>/dev/null) || {
    echo "[ERROR] Токен ghcr.io не найден в Keychain"
    exit 1
  }

  kubectl create secret docker-registry ghcr-pull-secret \
    -n "$NAMESPACE" \
    --docker-server=ghcr.io \
    --docker-username="$GHCR_USER" \
    --docker-password="$token" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  echo "[OK] imagePullSecret ghcr-pull-secret создан"
}

add_helm_repo() {
  local name="$1"
  local url="$2"
  if ! helm repo list 2>/dev/null | grep -q "^${name}[[:space:]]"; then
    helm repo add "$name" "$url" >/dev/null
    echo "[OK] Helm repo $name добавлен"
  else
    echo "[INFO] Helm repo $name уже существует"
  fi
  helm repo update "$name" >/dev/null
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

# Ждём, пока metrics-server начнёт отдавать метрики: HPA и VPA без него
# показывают <unknown> и не масштабируют вообще.
wait_for_metrics() {
  local timeout="${1:-180}"
  local waited=0
  echo "[INFO] Ожидание метрик от metrics-server (до ${timeout}s)..."
  while (( waited < timeout )); do
    if kubectl top nodes &>/dev/null; then
      echo "[OK] metrics-server отдаёт метрики"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  echo "[ERROR] metrics-server не отдал метрики за ${timeout}s"
  return 1
}

# Локальный Locust ходит в Ingress через tunnel по IP: macOS может долго
# разрешать *.local. Заголовок Host сохраняет маршрутизацию Ingress.
prepare_locust_target() {
  if [ -z "${LOCUST_TARGET:-}" ]; then
    export LOCUST_TARGET="http://127.0.0.1"
    export LOCUST_HOST_HEADER="$API_HOST"
  fi
}

resolve_api_url() {
  if [ -n "${LOCUST_TARGET:-}" ]; then
    echo "$LOCUST_TARGET"
    return
  fi
  echo "http://$API_HOST"
}

check_api_reachable() {
  local url="$1"
  local reachable=1
  if [ -n "${LOCUST_HOST_HEADER:-}" ]; then
    curl -fsS --max-time 5 -H "Host: $LOCUST_HOST_HEADER" "$url/healthz" >/dev/null 2>&1 && reachable=0
  else
    curl -fsS --max-time 5 "$url/healthz" >/dev/null 2>&1 && reachable=0
  fi
  if [ "$reachable" -eq 0 ]; then
    echo "[OK] $url отвечает"
    return 0
  fi
  echo "[ERROR] $url не отвечает на /healthz"
  echo "  Проверьте: minikube tunnel запущен, Ingress $API_HOST доступен,"
  echo "  приложение задеплоено (./scripts/03-build-and-deploy.sh)."
  echo "  Либо укажите свой адрес: LOCUST_TARGET=http://127.0.0.1:8080 $0"
  return 1
}
