# Проект для демонстрации навыков для Python Enterpise

---

```
Студеникин Даниил 11-312

https://t.me/imperial_dan

```

## 2. Разработка Helm-чарта + Vault.

---

### Часть 1.

- Чарты лежат тут: [helm/app](helm/app)
- Результат работы установки релиза лежит [тут](helm/hw2_output.yaml)

![](img/Снимок%20экрана%202026-01-13%20в%2015.33.12.png)
![](img/Снимок%20экрана%202026-01-13%20в%2015.42.27.png)

### Часть 2. Интеграция с HashiCorp Vault

#### Что сделано

1. **Установлен Vault** через Helm chart в dev-режиме с ingress на `http://vault.local`
2. **Настроена AppRole аутентификация** для безопасного доступа к секретам
3. **Секреты перенесены в Vault** (KV v2 engine):
   - `secret/postgres` - username, password, database
   - `secret/backend` - username, password
4. **Удалены Kubernetes Secret ресурсы** - секреты передаются напрямую через environment variables
5. **Интегрирован helm-secrets с vals backend** - секреты автоматически подставляются из Vault при деплое
6. **Скрипт для деплоя с секретами из Vault**  [scripts/deploy-with-secrets.sh](scripts/deploy-with-secrets.sh)

#### Команды для воспроизведения

```bash
# Установка и настройка Vault
make vault-install          # Развернуть Vault
make vault-setup-secrets    # Создать секреты в Vault
make vault-setup-approle    # Настроить AppRole (скопировать ROLE_ID и SECRET_ID)

# Настройка .env
cp .env.example .env        # Создать .env
nano .env                   # Вставить VAULT_ROLE_ID и VAULT_SECRET_ID

# Деплой с секретами из Vault
make helm-deploy-secrets
```


#### Скриншоты

![](img/Снимок%20экрана%202026-01-13%20в%2015.58.27.png)
![](img/Снимок%20экрана%202026-01-13%20в%2016.00.26.png)
![](img/Снимок%20экрана%202026-01-13%20в%2016.27.57.png)
> **Подробная инструкция по воспроизведению:** [VAULT_QUICKSTART.md](VAULT_QUICKSTART.md)


---

