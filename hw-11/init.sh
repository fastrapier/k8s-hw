#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

# add_host правит /etc/hosts — запрашиваем sudo один раз в начале,
# чтобы деплой не встал на середине в ожидании пароля.
sudo -v

"$SCRIPT_DIR/01-helmfile-init.sh"
"$SCRIPT_DIR/02-deploy.sh"

echo ""
echo "[OK] Всё готово"
echo ""
echo "Проверки:"
echo "  ./scripts/03-check-metrics.sh   # метрики nginx в Prometheus"
echo "  ./scripts/04-check-logs.sh      # логи в Loki"
echo "  ./scripts/05-test-alert.sh      # контакты и алертинг Grafana"
