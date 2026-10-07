#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

sudo -v

"$SCRIPT_DIR/01-setup-vault.sh"
"$SCRIPT_DIR/02-vault-integration.sh"

echo "[OK] Всё готово"
