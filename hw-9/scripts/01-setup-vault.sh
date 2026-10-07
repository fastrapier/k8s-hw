#!/bin/bash
# Часть 2, шаг 1: Vault в dev-режиме + секреты + политика + AppRole.
# Идемпотентен: повторный запуск переустанавливает релиз и перезаписывает секреты.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube

echo "=== Minikube addons ==="
minikube -p "$MINIKUBE_PROFILE" addons enable ingress
minikube -p "$MINIKUBE_PROFILE" addons enable default-storageclass
minikube -p "$MINIKUBE_PROFILE" addons enable storage-provisioner

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

echo "=== Секрет docker-registry (GHCR) ==="
GHCR_TOKEN="$(ghcr_token_from_keychain)"
$VAULT_EXEC vault kv put secret/docker \
  registry="$GHCR_REGISTRY" \
  username="$GHCR_USER" \
  token="$GHCR_TOKEN" >/dev/null
echo "[OK] secret/docker записан (token=$(mask "$GHCR_TOKEN"))"
unset GHCR_TOKEN

echo "=== Секреты приложения ==="
$VAULT_EXEC vault kv put secret/postgres \
  username=hw9_user \
  password=hw9_password \
  database=hw9

$VAULT_EXEC vault kv put secret/backend \
  username=developer \
  password=password

echo "=== Политика app-policy ==="
cat <<'POLICY' | kubectl exec -i "$VAULT_POD" -n "$NAMESPACE" -- vault policy write app-policy -
path "secret/data/*" { capabilities = ["read", "list"] }
path "secret/metadata/*" { capabilities = ["read", "list"] }
path "sys/internal/ui/mounts/*" { capabilities = ["read"] }
path "sys/mounts" { capabilities = ["read"] }
POLICY

echo "=== AppRole ==="
$VAULT_EXEC vault auth enable approle 2>/dev/null || echo "[INFO] approle уже включён"

$VAULT_EXEC vault write auth/approle/role/app-role \
  token_policies="app-policy" \
  token_ttl=1h \
  token_max_ttl=4h

echo ""
echo "[OK] Vault настроен"
echo "[INFO] Vault UI: http://$VAULT_HOST (токен root, нужен minikube tunnel)"
echo "[INFO] Секреты: secret/docker, secret/postgres, secret/backend"
