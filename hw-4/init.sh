#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

sudo -v

"$SCRIPT_DIR/01-setup-vault.sh"
"$SCRIPT_DIR/02-deploy-rabbitmq.sh"
"$SCRIPT_DIR/03-deploy-redis.sh"
"$SCRIPT_DIR/04-build-and-deploy.sh"

echo "[OK] Всё готово"
