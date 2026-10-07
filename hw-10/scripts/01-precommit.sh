#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "=== Установка инструментов ==="
require_cmd brew "https://brew.sh"

for tool in trufflehog pre-commit; do
  if command -v "$tool" &>/dev/null; then
    echo "[INFO] $tool уже установлен ($("$tool" --version 2>&1 | head -1))"
  else
    echo "[INFO] Устанавливаю $tool..."
    brew install "$tool"
  fi
done

echo ""
echo "=== Установка хуков в .git/hooks ==="
cd "$REPO_ROOT"
pre-commit install

echo ""
echo "=== Прогон по всему репозиторию ==="
# Первый прогон скачивает окружения хуков, поэтому долгий.
pre-commit run --all-files

echo ""
echo "[OK] pre-commit настроен"
echo "[INFO] Хуки: $REPO_ROOT/.pre-commit-config.yaml"
echo "[INFO] Разовый прогон вручную: pre-commit run --all-files"
echo "[INFO] Обойти хук в исключительном случае: SKIP=trufflehog git commit ..."
