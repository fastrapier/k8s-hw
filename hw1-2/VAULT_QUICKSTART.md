# Быстрый старт с Vault

## Минимальная последовательность команд

### 1. Подготовка окружения
```bash
# Установить vals (если нет)
brew install vals  # macOS
```

### 2. Развертывание и настройка Vault
```bash
# Шаг 1: Установить Vault
make vault-install

# Шаг 2: Создать секреты в Vault
make vault-setup-secrets

# Шаг 3: Настроить AppRole и получить credentials
make vault-setup-approle
```

**Важно:** Скопируйте `VAULT_ROLE_ID` и `VAULT_SECRET_ID` из вывода команды!

### 3. Настройка .env
```bash
# Создать .env файл
cp .env.example .env

# Вставить полученные VAULT_ROLE_ID и VAULT_SECRET_ID в .env
nano .env
```

Пример `.env`:
```bash
VAULT_ADDR=http://vault.local
VAULT_ROLE_ID=6ff196ed-4da1-28c5-3e17-ec47f8eebc7f
VAULT_SECRET_ID=16465d64-f160-c9db-43a9-09a9e24bbea8
```

### 4. Деплой приложения
```bash
# Запустить деплой с секретами из Vault
make helm-deploy-secrets
```

### 5. Проверка
```bash
# Проверить поды
kubectl get pods -n k8s-hw

# Проверить что секреты подставлены
kubectl exec -n k8s-hw deployment/backend-deployment -- env | grep -E "^(username|password)="

# Проверить Vault UI
open http://vault.local
# Token: root
```

## Альтернатива: использование root token (только для быстрого тестирования)

Для быстрого тестирования можно использовать root token вместо AppRole:

```bash
# В .env использовать:
VAULT_ADDR=http://vault.local
VAULT_TOKEN=root
```

## Удаление
```bash
# Удалить приложение
helm uninstall app -n k8s-hw

# Удалить Vault
make vault-uninstall
```

## Troubleshooting

### vals не найден
```bash
# macOS
brew install vals

# Linux
wget https://github.com/helmfile/vals/releases/latest/download/vals_linux_amd64.tar.gz
tar -xzf vals_linux_amd64.tar.gz
sudo mv vals /usr/local/bin/
```

### Vault pod не запускается
```bash
# Проверить логи
kubectl logs vault-0 -n k8s-hw

# Переустановить
make vault-uninstall
make vault-install
```

### helm-secrets не работает
```bash
# Проверить установку
helm plugin list

# Переустановить
helm plugin uninstall secrets
helm plugin install https://github.com/jkroepke/helm-secrets
```

