#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_node
cd "$PROJECT_ROOT"

echo "=== semantic-release --dry-run (какая версия получится) ==="

if [ -z "${GITHUB_TOKEN:-}" ]; then
  if command -v gh &>/dev/null && GITHUB_TOKEN=$(gh auth token 2>/dev/null); then
    export GITHUB_TOKEN
  else
    echo "[WARN] GITHUB_TOKEN не задан и gh не авторизован — пропускаю dry-run."
    echo "       Задайте: export GITHUB_TOKEN=\$(gh auth token)"
    exit 0
  fi
fi
export GITHUB_TOKEN

if [ ! -d node_modules ]; then
  echo "[INFO] Установка зависимостей semantic-release..."
  npm ci --no-audit --no-fund
fi

# semantic-release проверяет, что текущая ветка настроена как релизная И существует
# в origin. Локально мы обычно не на main, поэтому подставляем текущую ветку через
# --branches: версия считается по тем же правилам, только без публикации.
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "[INFO] Ветка: $BRANCH"

rm -f .version
npx semantic-release --dry-run --no-ci --branches "$BRANCH" || {
  echo "[WARN] dry-run завершился с ошибкой (частая причина — ветка ещё не запушена в origin)"
  exit 0
}

if [ -s .version ]; then
  echo ""
  echo "[OK] Следующая версия: $(cat .version)"
  echo "     Тег: v$(cat .version), образ: $GHCR_REPO:$(cat .version)"
else
  echo ""
  echo "[INFO] Релиз не требуется: нет коммитов, влияющих на версию"
fi
