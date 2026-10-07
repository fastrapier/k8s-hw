#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

# add_host в 02 требует sudo - спрашиваем пароль один раз в начале.
sudo -v

"$SCRIPT_DIR/01-precommit.sh"
"$SCRIPT_DIR/02-deploy-sonarqube.sh"
"$SCRIPT_DIR/03-configure-sonarqube.sh"

echo ""
echo "[OK] Всё готово"
echo ""
echo "Дальше по желанию:"
echo "  ./scripts/04-sonar-scan-local.sh   # прогнать анализ локально"
echo "  ./scripts/05-trivy-local.sh        # прогнать Trivy локально"
echo "  ./scripts/06-trufflehog-local.sh   # прогнать TruffleHog локально"
