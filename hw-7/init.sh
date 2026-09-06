#!/bin/bash
# Развёртывание инфраструктуры ДЗ 7.
#
# Нагрузочные скрипты (05, 06, 07) сюда не входят: они интерактивные,
# идут минутами и запускаются отдельно — см. CHECKLIST.MD.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

sudo -v

"$SCRIPT_DIR/01-metrics-server.sh"
"$SCRIPT_DIR/02-install-vpa.sh"
"$SCRIPT_DIR/03-build-and-deploy.sh"
"$SCRIPT_DIR/08-locust-operator.sh"

echo ""
echo "[OK] Всё готово"
echo ""
echo "Дальше — нагрузочная часть:"
echo "  ./scripts/04-measure.sh          # потребление в покое (часть 1)"
echo "  ./scripts/05-locust-local.sh     # одиночный прогон (часть 2)"
echo "  ./scripts/06-find-max-users.sh   # поиск максимума пользователей (часть 2)"
echo "  ./scripts/07-hpa-demo.sh         # HPA под нагрузкой + рекомендации VPA (часть 3)"
