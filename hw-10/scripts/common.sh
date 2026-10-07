#!/bin/bash

NAMESPACE="k8s-hw10"
SONAR_HOST="sonarqube-hw10.local"
SONAR_RELEASE="sonarqube"
SONAR_CHART_VERSION="2026.4.1"
# Имя Service чарт собирает как <release>-<chart>, fullnameOverride не задаём.
SONAR_SVC="${SONAR_RELEASE}-sonarqube"
SONAR_PORT="9000"
SONAR_LOCAL_URL="http://127.0.0.1:${SONAR_PORT}"
SONAR_IN_CLUSTER_URL="http://${SONAR_SVC}.${NAMESPACE}.svc:${SONAR_PORT}"
SONAR_PROJECT_KEY="k8s-hw"
SONAR_TOKEN_NAME="hw10-ci"

# Секреты не хранятся в репозитории: пароль админа, passcode мониторинга и
# CI-токен лежат в macOS Keychain под этими именами сервисов.
KEYCHAIN_ACCOUNT="fastrapier"
KEYCHAIN_PASSWORD_SERVICE="sonarqube-hw10"
KEYCHAIN_PASSCODE_SERVICE="sonarqube-hw10-passcode"
KEYCHAIN_TOKEN_SERVICE="sonarqube-hw10-token"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
  local profile="${MINIKUBE_PROFILE:-$(minikube profile 2>/dev/null)}"
  profile="${profile#\* }"
  if [ -z "$profile" ]; then
    echo "[ERROR] Не выбран профиль minikube. Укажите MINIKUBE_PROFILE." >&2
    return 1
  fi
  export MINIKUBE_PROFILE="$profile"
  if ! minikube -p "$profile" status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    echo "[ERROR] Minikube '$profile' не запущен. Запустите: minikube start -p $profile"
    exit 1
  fi
  if ! kubectl config use-context "$profile" >/dev/null; then
    echo "[ERROR] В kubeconfig нет контекста '$profile'. Проверьте KUBECONFIG." >&2
    return 1
  fi
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
    helm repo update "$name" >/dev/null
    echo "[INFO] Helm repo $name уже существует (обновлён)"
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

# --- Keychain -----------------------------------------------------------------

keychain_get() {
  local service="$1"
  security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$service" -w 2>/dev/null
}

keychain_set() {
  local service="$1"
  local value="$2"
  security add-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$service" -w "$value" -U
  echo "[OK] Значение сохранено в Keychain (сервис $service)"
}

keychain_delete() {
  local service="$1"
  security delete-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$service" &>/dev/null \
    && echo "[OK] $service удалён из Keychain" \
    || echo "[INFO] $service в Keychain не найден"
}

# Пароль/passcode генерируется один раз и переиспользуется: иначе повторный
# запуск init.sh менял бы пароль и ломал уже выданный CI-токен.
keychain_get_or_create() {
  local service="$1"
  local existing
  existing=$(keychain_get "$service") || true
  if [ -n "$existing" ]; then
    echo "$existing"
    return
  fi
  local generated
  require_cmd openssl "входит в macOS" >&2
  generated="Hw10-$(openssl rand -hex 16)"
  security add-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$service" -w "$generated" -U
  echo "$generated"
}

# --- SonarQube ----------------------------------------------------------------

SONAR_PF_PID=""

sonar_port_forward() {
  if curl -sf -o /dev/null "${SONAR_LOCAL_URL}/api/system/status" 2>/dev/null; then
    echo "[INFO] ${SONAR_LOCAL_URL} уже доступен, port-forward не нужен"
    return
  fi
  kubectl port-forward "svc/$SONAR_SVC" -n "$NAMESPACE" "${SONAR_PORT}:${SONAR_PORT}" &>/dev/null &
  SONAR_PF_PID=$!
  sleep 3
  echo "[OK] port-forward svc/$SONAR_SVC ${SONAR_PORT} (pid $SONAR_PF_PID)"
}

sonar_port_forward_cleanup() {
  if [ -n "${SONAR_PF_PID:-}" ]; then
    kill "$SONAR_PF_PID" 2>/dev/null || true
  fi
}

# SonarQube поднимается несколько минут: сначала стартует БД и Elasticsearch,
# и только потом api/system/status отдаёт UP.
sonar_wait_up() {
  local timeout="${1:-900}"
  local waited=0
  echo "[INFO] Ожидание SonarQube UP (до ${timeout}s)..."
  while [ "$waited" -lt "$timeout" ]; do
    local status
    status=$(curl -sf "${SONAR_LOCAL_URL}/api/system/status" 2>/dev/null \
      | sed -n 's/.*"status":"\([A-Z]*\)".*/\1/p') || true
    if [ "$status" = "UP" ]; then
      echo "[OK] SonarQube UP"
      return 0
    fi
    sleep 10
    waited=$((waited + 10))
    echo "  ... ${waited}s, status=${status:-нет ответа}"
  done
  echo "[ERROR] SonarQube не поднялся за ${timeout}s"
  return 1
}
