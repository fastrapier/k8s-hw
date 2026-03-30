#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube

echo "=== Minikube addons ==="
minikube addons enable ingress
minikube addons enable default-storageclass
minikube addons enable storage-provisioner

echo "=== Vault Helm ==="
add_helm_repo hashicorp https://helm.releases.hashicorp.com
helm_cleanup_pending vault

helm upgrade vault hashicorp/vault \
  --install \
  --namespace "$NAMESPACE" --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --set "ui.enabled=true" \
  --set "ui.serviceType=ClusterIP" \
  --set "injector.enabled=false" \
  --set "server.ingress.enabled=true" \
  --set "server.ingress.ingressClassName=nginx" \
  --set "server.ingress.hosts[0].host=$VAULT_HOST" \
  --set "server.ingress.hosts[0].paths[0]=/" \
  --wait --timeout=5m

kubectl wait --for=condition=Ready "pod/$VAULT_POD" -n "$NAMESPACE" --timeout=300s

add_host "$VAULT_HOST"

VAULT_EXEC="kubectl exec $VAULT_POD -n $NAMESPACE --"

echo "=== Секреты ==="
$VAULT_EXEC vault kv put secret/rabbitmq \
  username=rabbitmq_user \
  password=rabbitmq_password

$VAULT_EXEC vault kv put secret/redis \
  password=redis_secret_pass

WEATHER_KEY=$(security find-generic-password -a "$GHCR_USER" -s openweathermap -w 2>/dev/null || echo "demo")
$VAULT_EXEC vault kv put secret/weather \
  api_key="$WEATHER_KEY"

NEWS_KEY=$(security find-generic-password -a "$GHCR_USER" -s newsapi -w 2>/dev/null || echo "demo")
$VAULT_EXEC vault kv put secret/news \
  api_key="$NEWS_KEY"

echo "=== Политики ==="
cat <<'POLICY' | kubectl exec -i "$VAULT_POD" -n "$NAMESPACE" -- vault policy write app-policy -
path "secret/data/*" { capabilities = ["read", "list"] }
path "sys/internal/ui/mounts/*" { capabilities = ["read"] }
path "sys/mounts" { capabilities = ["read"] }
POLICY

echo "=== AppRole ==="
$VAULT_EXEC vault auth enable approle 2>/dev/null || true

$VAULT_EXEC vault write auth/approle/role/app-role \
  token_policies="app-policy" \
  token_ttl=1h \
  token_max_ttl=4h

echo ""
echo "[OK] Vault установлен и настроен"
echo "[INFO] Vault UI: http://$VAULT_HOST (нужен minikube tunnel)"
