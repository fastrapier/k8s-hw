#!/bin/bash
# Часть 2, шаг 2: интеграция werf с Vault и деплой.
#
#   AppRole login -> docker-токен из Vault -> werf cr login
#                 -> секреты приложения через vals -> werf converge
#
# Ни один секрет не пишется на диск в открытом виде дольше, чем живёт скрипт:
# отрендеренные values и временный docker config удаляются по trap.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_minikube
ensure_werf
ensure_vals

RENDERED_VALUES="$PROJECT_ROOT/secret-values.rendered.yaml"
DOCKER_CONFIG_DIR=""

cleanup() {
  rm -f "$RENDERED_VALUES"
  if [ -n "$DOCKER_CONFIG_DIR" ]; then
    rm -rf "$DOCKER_CONFIG_DIR"
  fi
  vault_login_cleanup
}
trap cleanup EXIT

if ! kubectl get pod "$VAULT_POD" -n "$NAMESPACE" &>/dev/null; then
  echo "[ERROR] Vault не найден в namespace $NAMESPACE. Запустите scripts/01-setup-vault.sh"
  exit 1
fi

echo "=== 1/4 Vault: AppRole login ==="
vault_approle_login

echo "=== 2/4 Vault: docker-токен -> werf cr login ==="
DOCKER_USER="$(vault_read_field secret/docker username)"
DOCKER_REGISTRY="$(vault_read_field secret/docker registry)"
DOCKER_TOKEN="$(vault_read_field secret/docker token)"

if [ -z "$DOCKER_TOKEN" ]; then
  echo "[ERROR] secret/docker#token пуст — перезапустите scripts/01-setup-vault.sh"
  exit 1
fi
echo "[INFO] registry=$DOCKER_REGISTRY user=$DOCKER_USER token=$(mask "$DOCKER_TOKEN")"

# Отдельный docker config: в конфиге пользователя обычно стоит credsStore
# (Keychain), и тогда werf cr login не пишет auth в файл — а он нужен, чтобы
# чарт собрал imagePullSecret из --set-docker-config-json-value.
DOCKER_CONFIG_DIR="$(mktemp -d)"
export WERF_DOCKER_CONFIG="$DOCKER_CONFIG_DIR"

# Пароль передаётся через $WERF_PASSWORD, а не аргументом: аргументы видны в ps.
WERF_PASSWORD="$DOCKER_TOKEN" werf cr login "$DOCKER_REGISTRY" -u "$DOCKER_USER"
unset DOCKER_TOKEN

if ! grep -q '"auth"' "$WERF_DOCKER_CONFIG/config.json" 2>/dev/null; then
  echo "[ERROR] $WERF_DOCKER_CONFIG/config.json без секции auth:"
  echo "        imagePullSecret получится пустым, поды не смогут скачать образы."
  exit 1
fi
echo "[OK] $DOCKER_REGISTRY авторизован, docker config: $WERF_DOCKER_CONFIG"

echo "=== 3/4 Vault: секреты приложения через vals ==="
: > "$RENDERED_VALUES"
chmod 600 "$RENDERED_VALUES"
vals eval -f "$PROJECT_ROOT/secret-values.tpl.yaml" > "$RENDERED_VALUES"

if grep -q 'ref+vault://' "$RENDERED_VALUES"; then
  echo "[ERROR] vals не раскрыл часть ссылок ref+vault:// — проверьте пути в secret-values.tpl.yaml"
  exit 1
fi
echo "[OK] Секреты получены из Vault, ключи:"
grep -E '^\s+[a-z]+:' "$RENDERED_VALUES" | sed 's/:.*/: ***/' | sed 's/^/      /'

echo "=== 4/4 werf converge ==="
export DOCKER_BUILDKIT=0
cd "$PROJECT_ROOT"

werf converge --dev \
  --repo "$GHCR_REPO" \
  --release "$RELEASE" \
  --namespace "$NAMESPACE" \
  --values "$RENDERED_VALUES" \
  --set-docker-config-json-value

add_host "$APP_HOST"

echo ""
echo "[OK] werf-проект задеплоен"
echo "[INFO] Приложение: http://$APP_HOST/ (нужен minikube tunnel)"
echo "[INFO] Проверить:  kubectl get pods -n $NAMESPACE"
