#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

sudo -v

"$SCRIPT_DIR/01-release-dry-run.sh"
"$SCRIPT_DIR/02-deploy.sh" "${1:-}"

echo "[OK] Всё готово"
