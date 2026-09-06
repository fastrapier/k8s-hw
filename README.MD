# Kubernetes — домашние задания

```
Студеникин Даниил 11-312
https://t.me/imperial_dan
```

---

## Домашние задания

| # | Тема | Директория | Описание |
|---|---|---|---|
| 1-2 | Helm + Vault | [hw1-2/](hw1-2/) | Helm-чарт приложения, интеграция с HashiCorp Vault (AppRole, helm-secrets) |
| 3 | RabbitMQ + Celery | [hw-3/](hw-3/) | Брокер сообщений, Go Producer/Consumer, Python Celery/Flower/FastAPI |
| 4 | Redis + кэширование | [hw-4/](hw-4/) | Redis, RedisInsight, CacheManager с TTL, кэширование API-запросов |
| 9 | Werf | [hw-9/](hw-9/) | Рефакторинг чарта в werf-проект, helm submodules, глобальные values, интеграция с Vault |

---

### ДЗ 1-2: Helm-чарт + Vault

Разработка Helm-чарта для приложения с PostgreSQL, интеграция с HashiCorp Vault для управления секретами.

- Helm-чарты с подчартами (backend, postgres)
- Vault AppRole аутентификация
- helm-secrets + vals для подстановки секретов из Vault

Подробнее: [hw1-2/README.MD](hw1-2/README.MD)

---

### ДЗ 3: RabbitMQ + Celery

Подключение RabbitMQ как брокера сообщений. Два независимых пайплайна обработки задач:

- **Go** — Producer (CronJob) отправляет задачи, Consumer обрабатывает (OpenWeatherMap, NewsAPI)
- **Python** — Celery Worker выполняет задачи, FastAPI предоставляет HTTP API, Flower для мониторинга
- Все секреты хранятся в Vault, аутентификация через AppRole
- Сборка и деплой через werf + GitHub Container Registry
- Идемпотентные скрипты: `init.sh` для развёртывания, `teardown.sh` для очистки

Подробнее: [hw-3/README.MD](hw-3/README.MD) | Чеклист для защиты: [hw-3/CHECKLIST.MD](hw-3/CHECKLIST.MD)

---

### ДЗ 4: Redis и кэширование

Развертывание Redis и RedisInsight, реализация CacheManager с TTL:

- **Redis** — StatefulSet на базе redis-stack-server, Headless Service + LoadBalancer, пароль из Vault
- **RedisInsight** — Helm-чарт heywood8/redisinsight с Ingress
- **CacheManager** — Go-модуль для работы с Redis (Get/Set/Exists + TTL)
- **Кэширование API** — CACHE HIT из Redis или API CALL + CACHE SET с TTL (5 мин погода, 10 мин новости)
- Изолированный namespace `k8s-hw4`

Подробнее: [hw-4/README.MD](hw-4/README.MD) | Чеклист для защиты: [hw-4/CHECKLIST.MD](hw-4/CHECKLIST.MD)

---

### ДЗ 9: Werf

Приложение из ДЗ 1-2 (Go HTTP API + PostgreSQL) переехало из «чарт + Makefile + helm-secrets»
в самодостаточный werf-проект:

- **werf-проект** — `werf.yaml` с тремя образами (app, cron, migrations) и исходниками рядом
- **Helm submodules** — сабчарты `backend` и `postgres` в `.helm/charts/`, `dependencies` с `condition`
- **Глобальные values** — порты, имена сервисов, хост Ingress и слоты под секреты в `global`
- **Интеграция с Vault** — один скрипт: AppRole login → docker-токен → `werf cr login` →
  секреты через `vals` → `werf converge --values`
- В репозитории нет ни токена, ни пароля: только `ref+vault://`-ссылки
- Изолированный namespace `k8s-hw9`, образы `ghcr.io/fastrapier/hw9`

Подробнее: [hw-9/README.MD](hw-9/README.MD) | Чеклист для защиты: [hw-9/CHECKLIST.MD](hw-9/CHECKLIST.MD)
