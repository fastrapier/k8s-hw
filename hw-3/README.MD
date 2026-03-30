# ДЗ 3 — RabbitMQ + Celery в Kubernetes

## Оглавление

- [Архитектура](#архитектура)
- [Структура проекта](#структура-проекта)
- [Пререквизиты](#пререквизиты)
- [Быстрый старт](#быстрый-старт)
- [Что делает каждый скрипт](#что-делает-каждый-скрипт)
- [Компоненты системы](#компоненты-системы)
- [Доступ к UI](#доступ-к-ui)
- [Чеклист для защиты](#чеклист-для-защиты)
- [Полезные команды](#полезные-команды)
- [Очистка](#очистка)

---

## Архитектура

```
┌────────────────────────────────────── Kubernetes (Minikube) ──────────────────────────────────────┐
│                                                                                                   │
│   ┌─── Go Pipeline ──────────────────────────┐   ┌─── Python/Celery Pipeline ──────────────────┐ │
│   │                                           │   │                                             │ │
│   │  CronJob (каждую минуту)                  │   │  Пользователь                               │ │
│   │   producer-weather ──┐                    │   │     │                                       │ │
│   │   producer-news    ──┤                    │   │     ▼ HTTP                                  │ │
│   │                      ▼                    │   │  FastAPI (celery-api)                       │ │
│   │               ┌────────────┐              │   │     │                                       │ │
│   │               │  RabbitMQ  │◄─────────────┼───┤     ▼                                       │ │
│   │               └─────┬──────┘              │   │  Celery Worker ──► OpenWeatherMap / NewsAPI │ │
│   │                     │                     │   │                                             │ │
│   │         ┌───────────┴──────────┐          │   │  Flower (мониторинг)                       │ │
│   │         ▼                      ▼          │   │                                             │ │
│   │  consumer-weather      consumer-news      │   └─────────────────────────────────────────────┘ │
│   │    ▼                      ▼               │                                                   │
│   │  OpenWeatherMap API    NewsAPI             │   ┌─── Инфраструктура ─────────────────────────┐ │
│   └───────────────────────────────────────────┘   │  Vault (секреты, AppRole)                   │ │
│                                                   └─────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Два независимых пайплайна работают через общий RabbitMQ, но используют **разные очереди и exchange**:

| | Go (Producer/Consumer) | Python (Celery) |
|---|---|---|
| Отправитель | CronJob (автоматически, раз в минуту) | Пользователь через HTTP API |
| Exchange/Очереди | `api_tasks` → `weather`, `news` | `celery` (стандартная) |
| Обработчик | consumer-weather, consumer-news | Celery Worker |
| Мониторинг | `kubectl logs` | Flower UI |

---

## Структура проекта

```
hw-3/
├── init.sh                        # Точка входа — запускает всё
├── teardown.sh                    # Полная очистка
├── TASK.MD                        # Задание
│
├── scripts/                       # Общие скрипты
│   ├── common.sh                  # Общие функции (ensure_*, create_*_secret)
│   ├── 01-setup-vault.sh          # Vault: установка, секреты, политики, AppRole
│   ├── 02-deploy-rabbitmq.sh      # RabbitMQ: Helm + vals (секреты из Vault)
│   ├── 03-build-and-deploy.sh     # Go: сборка werf + деплой consumer/producer
│   └── 04-deploy-celery.sh        # Python: сборка werf + деплой Celery/FastAPI/Flower
│
├── helm/                          # Общая инфраструктура
│   └── rabbitmq-values.yaml       # Values для RabbitMQ (секреты через vals)
│
├── go/                            # Go-приложение (отдельный werf-проект)
│   ├── cmd/
│   │   ├── producer/main.go       # Producer — отправляет задачи в RabbitMQ
│   │   └── consumer/main.go       # Consumer — слушает очередь, вызывает API
│   ├── internal/
│   │   ├── rabbitmq/connection.go # Подключение к RabbitMQ, exchange, queue
│   │   ├── vault/client.go        # Клиент Vault (AppRole auth)
│   │   └── tasks/
│   │       ├── weather.go         # Задача: запрос погоды через OpenWeatherMap
│   │       └── news.go            # Задача: запрос новостей через NewsAPI
│   ├── docker/
│   │   ├── producer.Dockerfile
│   │   └── consumer.Dockerfile
│   ├── go.mod, go.sum
│   ├── werf.yaml                  # werf: образы producer и consumer
│   └── .helm/                     # Helm-чарт для Go-приложений
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── configmap.yaml     # VAULT_ADDR, RMQ_HOST
│           ├── producer-job.yaml  # CronJob для producer-weather и producer-news
│           ├── consumer-weather.yaml
│           ├── consumer-news.yaml
│           └── secret.yaml
│
└── celery/                        # Python/Celery-приложение (отдельный werf-проект)
    ├── app/
    │   ├── celery_app.py          # Инициализация Celery
    │   ├── celeryconfig.py        # Конфигурация (broker_url, backend)
    │   ├── tasks.py               # Задачи: fetch_weather, fetch_news
    │   ├── api.py                 # FastAPI: HTTP-эндпоинты для задач
    │   └── vault.py               # Python-клиент Vault (AppRole auth)
    ├── docker/
    │   ├── worker.Dockerfile
    │   └── api.Dockerfile
    ├── requirements.txt
    ├── werf.yaml                  # werf: образы worker и api
    └── .helm/                     # Helm-чарт для Celery
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
            ├── configmap.yaml
            ├── celery-worker.yaml # Deployment для Celery worker
            ├── flower.yaml        # Deployment + Service + Ingress для Flower
            ├── api-deployment.yaml
            ├── api-service.yaml
            └── api-ingress.yaml   # Ingress: celery-api.local
```

---

## Пререквизиты

### Утилиты

| Утилита | Установка |
|---|---|
| minikube | `brew install minikube` |
| kubectl | `brew install kubectl` |
| helm | `brew install helm` |
| vals | `brew install vals` |
| werf | `curl -sSL https://werf.io/install.sh \| bash` |
| docker | Docker Desktop |

### API-ключи в macOS Keychain

```bash
# GitHub PAT (write:packages) — для публикации Docker-образов в ghcr.io
security add-generic-password -a fastrapier -s ghcr.io -w YOUR_GITHUB_TOKEN -U

# OpenWeatherMap API Key
security add-generic-password -a fastrapier -s openweathermap -w YOUR_KEY -U

# NewsAPI Key
security add-generic-password -a fastrapier -s newsapi -w YOUR_KEY -U
```

---

## Быстрый старт

```bash
# 1. Запустить Minikube
minikube start

# 2. В отдельном терминале — запустить tunnel (нужен для Ingress)
minikube tunnel

# 3. Развернуть всё одной командой
cd hw-3
./init.sh
```

Скрипт `init.sh` **идемпотентный** — можно запускать повторно без побочных эффектов.

---

## Что делает каждый скрипт

### `01-setup-vault.sh`
1. Включает аддоны Minikube: `ingress`, `default-storageclass`, `storage-provisioner`
2. Устанавливает Vault через Helm (dev-режим, root token = `root`)
3. Создаёт секреты в Vault:
   - `secret/rabbitmq` — логин/пароль RabbitMQ
   - `secret/weather` — API-ключ OpenWeatherMap (из Keychain)
   - `secret/news` — API-ключ NewsAPI (из Keychain)
4. Создаёт политики: `app-policy` (доступ ко всем секретам) и `rabbitmq-policy`
5. Настраивает AppRole аутентификацию (более безопасная альтернатива root-токену)

### `02-deploy-rabbitmq.sh`
1. Получает AppRole-токен из Vault
2. Рендерит values для RabbitMQ через `vals` (подставляет логин/пароль из Vault)
3. Устанавливает RabbitMQ через Helm (чарт Cloud Pirates)
4. Настраивает Ingress: `rabbitmq.local`

### `03-build-and-deploy.sh`
1. Собирает Docker-образы Go-приложений (producer, consumer) через `werf`
2. Пушит образы в GitHub Container Registry (`ghcr.io/fastrapier/hw3`)
3. Создаёт K8s-секреты: `vault-approle`, `ghcr-pull-secret`
4. Деплоит через `werf converge`:
   - **CronJob** `producer-weather` / `producer-news` — отправляют задачи каждую минуту
   - **Deployment** `consumer-weather` / `consumer-news` — слушают очереди и обрабатывают

### `04-deploy-celery.sh`
1. Создаёт K8s-секрет `celery-broker` (AMQP URL из Vault)
2. Собирает Docker-образы Python-приложений (worker, api) через `werf`
3. Пушит образы в `ghcr.io/fastrapier/hw3-celery`
4. Деплоит через `werf converge`:
   - **Deployment** `celery-worker` — Celery-воркер
   - **Deployment** `celery-api` — FastAPI-сервер + Ingress (`celery-api.local`)
   - **Deployment** `flower` — мониторинг Celery

---

## Компоненты системы

### Vault
- **Назначение**: централизованное хранение секретов (API-ключи, пароли)
- **Аутентификация**: AppRole (role_id + secret_id → временный токен)
- **Секреты**: `secret/rabbitmq`, `secret/weather`, `secret/news`

### RabbitMQ
- **Назначение**: брокер сообщений для Go и Celery приложений
- **Аутентификация**: логин/пароль из Vault через helm-secrets (vals)
- **Exchange**: `api_tasks` (direct, durable) для Go; `celery` (direct) для Celery

### Go Producer (CronJob)
- Запускается каждую минуту
- Подключается к RabbitMQ (credentials из Vault через AppRole)
- Публикует durable-сообщение в exchange `api_tasks` с routing key `weather`/`news`

### Go Consumer (Deployment)
- Получает очередь из CLI-аргумента (`--queue weather` / `--queue news`)
- Создаёт durable-очередь и биндит к exchange
- Обрабатывает сообщения: вызывает API (ключ из Vault), сохраняет JSON, отправляет ACK
- Логирует результат (температура, заголовки новостей)

### Celery Worker (Deployment)
- Слушает очередь `celery` в RabbitMQ
- Задачи: `fetch_weather(city)`, `fetch_news(query)`
- API-ключи получает из Vault через AppRole

### FastAPI (Deployment + Ingress)
- `POST /tasks/weather?city=Moscow` — создаёт задачу погоды
- `POST /tasks/news?q=technology` — создаёт задачу новостей
- `GET /tasks/{task_id}` — статус задачи (AsyncResult)
- `GET /health` — проверка работоспособности

### Flower (Deployment + Ingress)
- Веб-интерфейс мониторинга Celery
- Доступен через Ingress: `flower.local`
- Показывает: активные воркеры, задачи, статистику

---

## Доступ к UI

> **Важно**: для работы Ingress необходимо запустить `minikube tunnel` в отдельном терминале.

| Сервис | URL | Примечание |
|---|---|---|
| Vault UI | http://vault.local | Токен: `root` |
| RabbitMQ Management | http://rabbitmq.local | Логин: `rabbitmq_user` / `rabbitmq_password` |
| FastAPI (Celery) | http://celery-api.local | Swagger: http://celery-api.local/docs |
| Flower | http://flower.local | Мониторинг Celery |

---

## Чеклист для защиты

Пошаговый план демонстрации с готовыми командами: **[CHECKLIST.MD](CHECKLIST.MD)**

---

## Полезные команды

```bash
# Все поды
kubectl get pods -n k8s-hw

# Логи consumer-ов (Go)
kubectl logs -f deployment/consumer-weather -n k8s-hw
kubectl logs -f deployment/consumer-news -n k8s-hw

# Логи Celery worker
kubectl logs -f deployment/celery-worker -n k8s-hw

# Логи FastAPI
kubectl logs -f deployment/celery-api -n k8s-hw

# Очереди RabbitMQ
kubectl exec rabbitmq-0 -n k8s-hw -- rabbitmqctl list_queues name messages consumers

# Exchanges и bindings
kubectl exec rabbitmq-0 -n k8s-hw -- rabbitmqctl list_exchanges name type
kubectl exec rabbitmq-0 -n k8s-hw -- rabbitmqctl list_bindings source_name destination_name routing_key

# Секреты Vault
kubectl exec vault-0 -n k8s-hw -- vault kv get secret/rabbitmq
kubectl exec vault-0 -n k8s-hw -- vault kv get secret/weather

# Flower
open http://flower.local
```

---

## Очистка

```bash
# Удалить все ресурсы
./teardown.sh

# Полностью удалить namespace
kubectl delete namespace k8s-hw

# Остановить Minikube
minikube stop
```
