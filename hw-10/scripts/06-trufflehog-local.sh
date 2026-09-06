#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Локальный аналог джобы trufflehog: сканирует всю историю репозитория так же,
# как это делает CI на push в main.
#
# Флаги:
#   --all   добавить unverified - заведомо невалидные срабатывания.
#           Так видно, что детекторы работают (см. CHECKLIST.MD).

require_cmd brew "https://brew.sh"
if ! command -v trufflehog &>/dev/null; then
  echo "[INFO] Устанавливаю trufflehog..."
  brew install trufflehog
fi

RESULTS="verified,unknown"
if [ "${1:-}" = "--all" ]; then
  RESULTS="verified,unknown,unverified"
fi

cd "$REPO_ROOT"

echo "=== История репозитория (--results=$RESULTS) ==="
trufflehog git "file://$REPO_ROOT" \
  --results="$RESULTS" \
  --no-update \
  --fail
echo "[OK] Секретов в истории не найдено"

echo ""
echo "=== Рабочее дерево (--results=$RESULTS) ==="
trufflehog filesystem "$REPO_ROOT" \
  --results="$RESULTS" \
  --no-update \
  --fail
echo "[OK] Секретов в рабочем дереве не найдено"
