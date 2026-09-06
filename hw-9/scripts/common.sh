#!/bin/bash

NAMESPACE="k8s-hw9"
RELEASE="hw9"
VAULT_POD="vault-0"
VAULT_HOST="vault-hw9.local"
APP_HOST="app-hw9.local"
GHCR_REGISTRY="ghcr.io"
GHCR_USER="fastrapier"
GHCR_REPO="$GHCR_REGISTRY/$GHCR_USER/hw9"
PULL_SECRET="ghcr-pull-secret"

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
  kubectl config use-context minikube &>/dev/null
}

ensure_werf() {
  require_cmd werf "curl -sSL https://werf.io/install.sh | bash"
}

ensure_vals() {
  require_cmd vals "brew install vals"
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

# Токен GHCR берётся из macOS Keychain и попадает только в Vault:
# дальше все потребители (werf cr login, imagePullSecret) читают его из Vault.
ghcr_token_from_keychain() {
  security find-generic-password -a "$GHCR_USER" -s ghcr.io -w 2>/dev/null || {
    echo "[ERROR] Токен ghcr.io не найден в macOS Keychain" >&2
    echo "  Сохраните: security add-generic-password -a $GHCR_USER -s ghcr.io -w YOUR_GITHUB_TOKEN -U" >&2
    return 1
  }
}

mask() {
  local value="$1"
  if [ -z "$value" ]; then
    echo "<empty>"
  else
    echo "${value:0:4}...(${#value} символов)"
  fi
}

# AppRole login: role_id + secret_id -> client token.
# Port-forward нужен, чтобы vals (работает на хосте) видел Vault по localhost.
vault_approle_login() {
  local vault_exec="kubectl exec $VAULT_POD -n $NAMESPACE --"

  kubectl port-forward "$VAULT_POD" -n "$NAMESPACE" 8200:8200 &>/dev/null &
  VAULT_PF_PID=$!
  sleep 2

  export VAULT_ADDR="http://127.0.0.1:8200"
  export VAULT_TOKEN
  VAULT_TOKEN=$($vault_exec sh -c '
    ROLE_ID=$(vault read -field=role_id auth/approle/role/app-role/role-id) &&
    SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/app-role/secret-id) &&
    vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID"
  ')

  if [ -z "$VAULT_TOKEN" ]; then
    vault_login_cleanup
    echo "[ERROR] Не удалось получить токен через AppRole"
    exit 1
  fi

  echo "[OK] Vault AppRole login выполнен (token=$(mask "$VAULT_TOKEN"))"
}

vault_login_cleanup() {
  if [ -n "${VAULT_PF_PID:-}" ]; then
    kill "$VAULT_PF_PID" 2>/dev/null || true
    unset VAULT_PF_PID
  fi
}

# Чтение поля секрета из Vault под AppRole-токеном: так проверяется,
# что политика app-policy действительно даёт доступ к secret/data/*.
vault_read_field() {
  local path="$1"
  local field="$2"
  kubectl exec "$VAULT_POD" -n "$NAMESPACE" -- \
    env VAULT_TOKEN="$VAULT_TOKEN" vault kv get -field="$field" "$path"
}
