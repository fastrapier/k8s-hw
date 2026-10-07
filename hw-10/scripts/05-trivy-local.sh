#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Локальный аналог джобы trivy. Первый прогон качает базу уязвимостей (~50 МБ).

require_cmd brew "https://brew.sh"
if ! command -v trivy &>/dev/null; then
  echo "[INFO] Устанавливаю trivy..."
  brew install trivy
fi

cd "$REPO_ROOT"

echo "=== Отчёт: уязвимости, секреты, misconfig (HIGH + CRITICAL) ==="
# Ровно то же, что делает шаг 1 в CI. exit-code не задан: только смотрим.
# --show-suppressed: подавленные находки выводятся отдельной таблицей вместе
# с обоснованием из .trivyignore.yaml, чтобы исключения не были невидимыми.
trivy fs \
  --scanners vuln,secret,misconfig \
  --severity HIGH,CRITICAL \
  --ignorefile .trivyignore.yaml \
  --show-suppressed \
  .

echo ""
echo "=== Гейт: CRITICAL с доступным фиксом ==="
# То же, что валит пайплайн в CI. Здесь --ignorefile указан явно: YAML-формат
# автоматически не подхватывается, в отличие от обычного .trivyignore.
if trivy fs \
  --scanners vuln \
  --severity CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  --ignorefile .trivyignore.yaml \
  --quiet \
  .
then
  echo "[OK] Гейт пройден: новых CRITICAL с доступным фиксом нет"
else
  echo ""
  echo "[FAIL] Гейт не пройден - в CI этот пайплайн будет красным."
  echo "       Либо обновите зависимость, либо осознанно внесите ID"
  echo "       в .trivyignore.yaml (с обоснованием и датой истечения)."
  exit 1
fi
