#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

sudo -v

"$SCRIPT_DIR/01-release-dry-run.sh"
"$SCRIPT_DIR/02-deploy.sh" "${1:-}"

# Раннер (часть 2) от деплоя приложения не зависит: он нужен, только чтобы
# деплой умел приезжать из пайплайна. SKIP_RUNNER=1 — если демонстрируется
# только часть 1 или нет PAT для регистрации раннера.
if [ "${SKIP_RUNNER:-0}" = "1" ]; then
  echo "[INFO] SKIP_RUNNER=1 — self-hosted раннер не разворачивается"
else
  "$SCRIPT_DIR/03-deploy-runner.sh"
fi

echo "[OK] Всё готово"
