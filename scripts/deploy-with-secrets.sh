#!/usr/bin/env bash
set -euo pipefail

# Скрипт для деплоя приложения с использованием helm-secrets и vals
# helm-secrets используется с vals в качестве backend для подстановки секретов из Vault
# Секреты извлекаются из Vault и подставляются в values при деплое

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Загружаем переменные окружения из .env
if [ -f "${PROJECT_ROOT}/.env" ]; then
    echo "[INFO] Загрузка переменных из .env"
    # Экспортируем переменные, игнорируя комментарии и пустые строки
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
else
    echo "[ERROR] Файл .env не найден!"
    echo "[INFO] Создайте .env на основе .env.example и заполните значения"
    exit 1
fi

# Проверяем наличие необходимых переменных
if [ -z "${VAULT_ADDR:-}" ]; then
    echo "[ERROR] VAULT_ADDR не установлен в .env"
    exit 1
fi

# Проверяем аутентификацию (AppRole или Token)
if [ -n "${VAULT_ROLE_ID:-}" ] && [ -n "${VAULT_SECRET_ID:-}" ]; then
    echo "[INFO] Используется AppRole аутентификация"
    echo "[INFO] VAULT_ADDR=${VAULT_ADDR}"
    echo "[INFO] VAULT_ROLE_ID=${VAULT_ROLE_ID:0:10}..."

    # Получаем токен через AppRole login
    echo "[INFO] Получение токена через AppRole..."
    LOGIN_RESPONSE=$(curl -s -X POST "${VAULT_ADDR}/v1/auth/approle/login" \
        -d "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}")

    # Проверяем успешность запроса
    if echo "$LOGIN_RESPONSE" | grep -q "client_token"; then
        export VAULT_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"client_token":"[^"]*"' | cut -d'"' -f4)
        echo "[OK] Токен получен успешно"
    else
        echo "[ERROR] Не удалось получить токен через AppRole"
        echo "$LOGIN_RESPONSE"
        exit 1
    fi
elif [ -n "${VAULT_TOKEN:-}" ]; then
    echo "[INFO] Используется Token аутентификация"
    echo "[INFO] VAULT_ADDR=${VAULT_ADDR}"
    echo "[INFO] VAULT_TOKEN=${VAULT_TOKEN:0:5}..."
else
    echo "[ERROR] Не установлены ни VAULT_ROLE_ID/VAULT_SECRET_ID, ни VAULT_TOKEN"
    exit 1
fi

# Параметры деплоя
RELEASE_NAME="${RELEASE_NAME:-app}"
NAMESPACE="${NAMESPACE:-k8s-hw}"
CHART_PATH="${PROJECT_ROOT}/helm/app"
VALUES_FILE="${CHART_PATH}/values.yaml"

echo "[INFO] Деплой release=${RELEASE_NAME} в namespace=${NAMESPACE}"

# Проверяем доступность Vault
echo "[INFO] Проверка доступности Vault..."
VAULT_NAMESPACE="${NAMESPACE}"

# Проверяем что Vault pod запущен
if ! kubectl get pod vault-0 -n "${VAULT_NAMESPACE}" &> /dev/null; then
    echo "[ERROR] Vault pod не найден в namespace ${VAULT_NAMESPACE}"
    echo "[INFO] Запустите: make vault-install"
    exit 1
fi

# Проверяем доступность Vault API
if ! curl -s "${VAULT_ADDR}/v1/sys/health" &> /dev/null; then
    echo "[ERROR] Vault недоступен по адресу ${VAULT_ADDR}"
    echo "[INFO] Проверьте что ingress настроен и запись в /etc/hosts добавлена"
    exit 1
fi

echo "[OK] Vault доступен: ${VAULT_ADDR}"


# Устанавливаем vals если не установлен
if ! command -v vals &> /dev/null; then
    echo "[WARN] vals не установлен, устанавливаю..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install vals || {
            echo "[ERROR] Не удалось установить vals через brew"
            echo "[INFO] Установите вручную: https://github.com/helmfile/vals"
            exit 1
        }
    else
        echo "[ERROR] vals не установлен"
        echo "[INFO] Установите vals: https://github.com/helmfile/vals"
        exit 1
    fi
fi

# Создаём namespace если не существует
if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
    echo "[INFO] Создание namespace ${NAMESPACE}"
    kubectl create namespace "${NAMESPACE}"
fi

# Выполняем деплой с vals для подстановки секретов
echo "[INFO] Рендеринг values.yaml с подстановкой секретов из Vault"
RENDERED_VALUES="/tmp/values-rendered-$$.yaml"
vals eval -f "${VALUES_FILE}" > "${RENDERED_VALUES}"

echo "[INFO] Запуск helm upgrade --install"
cd "${PROJECT_ROOT}"

helm upgrade --install "${RELEASE_NAME}" "${CHART_PATH}" \
    --namespace "${NAMESPACE}" \
    --values "${RENDERED_VALUES}" \
    --wait \
    --timeout 10m \
    --create-namespace

# Удаляем временный файл с рендеренными values
rm -f "${RENDERED_VALUES}"

echo "[OK] Деплой завершён успешно!"
echo ""
echo "Проверить статус:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo ""
echo "Доступ к приложению:"
echo "  https://backend.local/"
echo ""
echo "Vault UI:"
echo "  ${VAULT_ADDR}"

