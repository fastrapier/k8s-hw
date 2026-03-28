#!/bin/bash

NAMESPACE="k8s-hw"
VAULT_POD="vault-0"
VAULT_HOST="vault.local"
RABBITMQ_HOST="rabbitmq.local"
GHCR_USER="fastrapier"
GHCR_REPO="ghcr.io/$GHCR_USER/hw3"
GHCR_REPO_CELERY="ghcr.io/$GHCR_USER/hw3-celery"
CELERY_API_HOST="celery-api.local"
FLOWER_HOST="flower.local"

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

add_host() {
  local host="$1"
  if grep -q "$host" /etc/hosts; then
    sudo sed -i '' "/$host/d" /etc/hosts
  fi
  echo "127.0.0.1 $host" | sudo tee -a /etc/hosts >/dev/null
  echo "[OK] $host -> 127.0.0.1"
}

ensure_vals() {
  require_cmd vals "brew install vals"
}

ensure_werf() {
  require_cmd werf "curl -sSL https://werf.io/install.sh | bash"
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
    --dry-run=client -o yaml | kubectl apply -f -

  echo "[OK] K8s imagePullSecret ghcr-pull-secret создан"
}

# Получает ROLE_ID и SECRET_ID из Vault AppRole и создаёт K8s Secret vault-approle
create_vault_approle_secret() {
  local vault_exec="kubectl exec $VAULT_POD -n $NAMESPACE --"

  echo "[INFO] Получение AppRole credentials из Vault..."
  local role_id secret_id
  role_id=$($vault_exec vault read -field=role_id auth/approle/role/app-role/role-id)
  secret_id=$($vault_exec vault write -field=secret_id -f auth/approle/role/app-role/secret-id)

  if [ -z "$role_id" ] || [ -z "$secret_id" ]; then
    echo "[ERROR] Не удалось получить AppRole credentials"
    exit 1
  fi

  kubectl create secret generic vault-approle \
    -n "$NAMESPACE" \
    --from-literal=VAULT_ROLE_ID="$role_id" \
    --from-literal=VAULT_SECRET_ID="$secret_id" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "[OK] K8s Secret vault-approle создан (role_id=${role_id:0:10}...)"
}

create_celery_broker_secret() {
  local vault_exec="kubectl exec $VAULT_POD -n $NAMESPACE --"
  local rmq_user rmq_pass rmq_host broker_url

  rmq_user=$($vault_exec vault kv get -field=username secret/rabbitmq)
  rmq_pass=$($vault_exec vault kv get -field=password secret/rabbitmq)
  rmq_host="rabbitmq.$NAMESPACE.svc.cluster.local"
  broker_url="amqp://${rmq_user}:${rmq_pass}@${rmq_host}:5672/"

  kubectl create secret generic celery-broker \
    -n "$NAMESPACE" \
    --from-literal=CELERY_BROKER_URL="$broker_url" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "[OK] K8s Secret celery-broker создан"
}

vault_login() {
  export VAULT_ADDR="http://$VAULT_HOST"
  local vault_exec="kubectl exec $VAULT_POD -n $NAMESPACE --"

  # Логин через AppRole прямо внутри пода (не требует tunnel/ingress)
  export VAULT_TOKEN
  VAULT_TOKEN=$($vault_exec sh -c '
    ROLE_ID=$(vault read -field=role_id auth/approle/role/app-role/role-id) &&
    SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/app-role/secret-id) &&
    vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID"
  ')

  if [ -z "$VAULT_TOKEN" ]; then
    echo "[ERROR] Не удалось получить токен через AppRole"
    exit 1
  fi

  echo "[OK] Vault AppRole login успешен (token=${VAULT_TOKEN:0:10}...)"
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
