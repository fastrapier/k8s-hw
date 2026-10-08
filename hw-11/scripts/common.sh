#!/bin/bash

NAMESPACE="k8s-hw11"
INGRESS_NAMESPACE="ingress-nginx"
PROMETHEUS_HOST="prometheus-hw11.local"
ALERTMANAGER_HOST="alertmanager-hw11.local"
GRAFANA_HOST="grafana-hw11.local"

KEYCHAIN_ACCOUNT="fastrapier"
KEYCHAIN_SMTP_SERVICE="smtp-hw11"
KEYCHAIN_GRAFANA_SERVICE="grafana-hw11"

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELMFILE="$HW_DIR/helmfile.yaml.gotmpl"
ENV_FILE="$HW_DIR/.env"

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
  require_cmd curl     "входит в macOS"
  require_cmd python3  "brew install python"
  require_cmd jq       "brew install jq"
}

ensure_minikube() {
  ensure_base
  local profile="${MINIKUBE_PROFILE:-$(minikube profile 2>/dev/null)}"
  profile="${profile#\* }"
  if [ -z "$profile" ]; then
    echo "[ERROR] Укажите MINIKUBE_PROFILE." >&2
    return 1
  fi
  export MINIKUBE_PROFILE="$profile"
  if ! minikube -p "$profile" status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    echo "[ERROR] Minikube '$profile' не запущен. Запустите: minikube start -p $profile"
    exit 1
  fi
  kubectl config use-context "$profile" >/dev/null
}

ensure_helmfile() {
  require_cmd helmfile "brew install helmfile"
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

keychain_get() {
  security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$1" -w 2>/dev/null
}

# Секреты не хранятся в репозитории: пароли берутся из macOS Keychain,
# несекретные параметры — из hw-11/.env (в git не попадает) или из окружения.
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    echo "[INFO] Загружен $ENV_FILE"
  fi

  if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
    GRAFANA_ADMIN_PASSWORD="$(keychain_get "$KEYCHAIN_GRAFANA_SERVICE")" || true
  fi
  if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
    require_cmd openssl "входит в macOS"
    GRAFANA_ADMIN_PASSWORD="Hw11-$(openssl rand -hex 16)"
    security add-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_GRAFANA_SERVICE" \
      -w "$GRAFANA_ADMIN_PASSWORD" -U
    echo "[OK] Пароль Grafana создан и сохранён в Keychain ($KEYCHAIN_GRAFANA_SERVICE)"
  fi

  GRAFANA_SMTP_ENABLED="${GRAFANA_SMTP_ENABLED:-false}"
  export GRAFANA_ADMIN_PASSWORD GRAFANA_SMTP_ENABLED
  case "$GRAFANA_SMTP_ENABLED" in
    false)
      echo "[INFO] SMTP выключен; правила работают, уведомления hw=11 заглушены."
      return 0
      ;;
    true) ;;
    *) echo "[ERROR] GRAFANA_SMTP_ENABLED должен быть true или false." >&2; return 1 ;;
  esac

  if [ -z "${GRAFANA_SMTP_PASSWORD:-}" ]; then
    GRAFANA_SMTP_PASSWORD="$(keychain_get "$KEYCHAIN_SMTP_SERVICE")" || true
  fi
  if [ -z "${GRAFANA_SMTP_PASSWORD:-}" ]; then
    echo "[ERROR] Не задан SMTP-токен (GRAFANA_SMTP_PASSWORD)."
    echo "  Это пароль приложения почтового провайдера, не основной пароль аккаунта."
    echo "  Положите в Keychain:"
    echo "    security add-generic-password -a $KEYCHAIN_ACCOUNT -s $KEYCHAIN_SMTP_SERVICE -w '<token>' -U"
    echo "  Как получить токен — README.MD, раздел «SMTP-токен»"
    exit 1
  fi

  if [ -z "${GRAFANA_SMTP_USER:-}" ]; then
    echo "[ERROR] Не задан GRAFANA_SMTP_USER (логин SMTP, обычно полный адрес почты)."
    echo "  Задайте его в $ENV_FILE (см. .env.example) или в окружении."
    exit 1
  fi

  GRAFANA_SMTP_HOST="${GRAFANA_SMTP_HOST:-smtp.gmail.com:587}"
  GRAFANA_SMTP_FROM_ADDRESS="${GRAFANA_SMTP_FROM_ADDRESS:-$GRAFANA_SMTP_USER}"
  ALERT_EMAIL="${ALERT_EMAIL:-$GRAFANA_SMTP_USER}"

  export GRAFANA_ADMIN_PASSWORD GRAFANA_SMTP_PASSWORD GRAFANA_SMTP_USER \
    GRAFANA_SMTP_HOST GRAFANA_SMTP_FROM_ADDRESS ALERT_EMAIL
}

# Открывает port-forward на сервис и глушит его при выходе из скрипта.
# Использование: port_forward svc/loki-gateway 8080 80  -> печатает базовый URL
PF_PIDS=()
# .local на macOS может задерживать каждый запрос из-за mDNS.
http_request() {
  curl --resolve "$PROMETHEUS_HOST:80:127.0.0.1" \
    --resolve "$GRAFANA_HOST:80:127.0.0.1" "$@"
}
port_forward() {
  local target="$1" local_port="$2" remote_port="$3"
  kubectl port-forward "$target" -n "$NAMESPACE" "$local_port:$remote_port" &>/dev/null &
  PF_PIDS+=("$!")
  local i
  for i in $(seq 1 30); do
    if nc -z 127.0.0.1 "$local_port" &>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "[ERROR] Не удалось поднять port-forward на $target"
  return 1
}

port_forward_cleanup() {
  local pid
  for pid in "${PF_PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
  PF_PIDS=()
}

# Базовый URL Prometheus: сначала пробуем ingress (нужен minikube tunnel),
# иначе откатываемся на port-forward.
prometheus_base_url() {
  if http_request -fsS --max-time 5 "http://$PROMETHEUS_HOST/-/ready" &>/dev/null; then
    BASE="http://$PROMETHEUS_HOST"
    return 0
  fi
  port_forward "svc/kube-prometheus-stack-prometheus" 19090 9090 >&2 || return 1
  echo "[INFO] Ingress $PROMETHEUS_HOST недоступен, использую port-forward" >&2
  BASE="http://127.0.0.1:19090"
}

grafana_base_url() {
  if http_request -fsS --max-time 5 "http://$GRAFANA_HOST/api/health" &>/dev/null; then
    BASE="http://$GRAFANA_HOST"
    return 0
  fi
  port_forward "svc/grafana" 13000 80 >&2 || return 1
  echo "[INFO] Ingress $GRAFANA_HOST недоступен, использую port-forward" >&2
  BASE="http://127.0.0.1:13000"
}
