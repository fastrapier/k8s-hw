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
| 8 | CI/CD | [hw-8/](hw-8/) | semantic-release, GitHub Actions: тег → сборка образа в GHCR → деплой |

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

### ДЗ 8: CI/CD

Пайплайн в GitHub Actions, где версия образа считается автоматически по Conventional Commits:

- **semantic-release** — считает следующую версию по сообщениям коммитов, создаёт git-тег `vX.Y.Z` и GitHub Release с release notes
- **Сборка образа по тегу** — buildx собирает `ghcr.io/fastrapier/hw8:<version>`, версия и git-sha зашиваются в бинарник через `-ldflags`
- **Деплой по тегу** — `helm upgrade --install` с `--set image.tag=<version>`; тот же чарт используется и локально
- **Приложение** — минимальный Go HTTP-сервис с `GET /healthz` и `GET /version`
- **Свой self-hosted раннер** — Actions Runner Controller ставится двумя OCI-чартами GitHub в minikube (`arc-systems` + `arc-runners`); джоба `deploy` уезжает на него и деплоит изнутри кластера, без kubeconfig в секретах
- На pull request — dry-run версии и сборка образа без push; реальный релиз только при push в `main`
- Изолированный namespace `k8s-hw8`

Workflow: [.github/workflows/hw8-release.yml](.github/workflows/hw8-release.yml)

Подробнее: [hw-8/README.MD](hw-8/README.MD) | Чеклист для защиты: [hw-8/CHECKLIST.MD](hw-8/CHECKLIST.MD)
