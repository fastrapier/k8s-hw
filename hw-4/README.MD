# ДЗ 4 — Redis и кэширование

## Архитектура

```
┌──────────────────────────── Kubernetes (Minikube, namespace: k8s-hw4) ────────────────────────────┐
│                                                                                                   │
│  CronJob (каждую минуту)                                                                         │
│   producer-weather ──┐                                                                            │
│   producer-news    ──┤                                                                            │
│                      ▼                                                                            │
│               ┌────────────┐         ┌─────────┐                                                  │
│               │  RabbitMQ  │         │  Redis   │                                                  │
│               └─────┬──────┘         └────┬─────┘                                                  │
│                     │                     │                                                        │
│         ┌───────────┴──────────┐          │ кэш (TTL)                                             │
│         ▼                      ▼          │                                                        │
│  consumer-weather      consumer-news ─────┘                                                       │
│    │                      │                                                                       │
│    │ CACHE HIT? ──► Redis │ CACHE HIT? ──► Redis                                                 │
│    │ CACHE MISS? ──► API  │ CACHE MISS? ──► API                                                  │
│    ▼                      ▼                                                                       │
│  OpenWeatherMap        NewsAPI              ┌──────────────┐                                       │
│                                             │ RedisInsight  │ (мониторинг Redis)                  │
│  ┌──────┐                                   └──────────────┘                                       │
│  │Vault │ (секреты: API-ключи, пароли Redis/RabbitMQ)                                             │
│  └──────┘                                                                                         │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Структура проекта

```
hw-4/
├── init.sh                        # Точка входа — запускает всё
├── teardown.sh                    # Полная очистка
├── TASK.MD                        # Задание
│
├── scripts/
│   ├── common.sh                  # Общие функции
│   ├── 01-setup-vault.sh          # Vault + секрет Redis
│   ├── 02-deploy-rabbitmq.sh      # RabbitMQ
│   ├── 03-deploy-redis.sh         # Redis (redis-stack-server) + RedisInsight
│   └── 04-build-and-deploy.sh     # Сборка werf + деплой
│
├── cmd/
│   ├── producer/main.go           # Producer — отправляет задачи в RabbitMQ
│   └── consumer/main.go           # Consumer — с Redis кэшированием
├── internal/
│   ├── cache/manager.go           # CacheManager — подключение к Redis, Get/Set/Exists с TTL
│   ├── rabbitmq/connection.go
│   ├── vault/client.go
│   └── tasks/
│       ├── weather.go             # Погода с кэшированием (TTL 5 мин)
│       └── news.go                # Новости с кэшированием (TTL 10 мин)
├── docker/
│   ├── producer.Dockerfile
│   └── consumer.Dockerfile
├── werf.yaml
├── .helm/                         # Helm-чарт
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── configmap.yaml         # VAULT_ADDR, RMQ_HOST, REDIS_HOST
│       ├── producer-job.yaml
│       ├── consumer-weather.yaml
│       ├── consumer-news.yaml
│       └── secret.yaml
│
└── helm/
    └── rabbitmq-values.yaml
```

## Что нового по сравнению с hw-3

| Компонент | Описание |
|---|---|
| Redis (redis-stack-server) | StatefulSet + Headless Service + LoadBalancer, пароль из Vault |
| RedisInsight | Helm-чарт heywood8/redisinsight с Ingress |
| CacheManager (`internal/cache/manager.go`) | Подключение к Redis, методы Get/Set/Exists с TTL |
| Кэширование API-задач | При CACHE HIT — данные из Redis; при MISS — вызов API → сохранение в Redis |

## Быстрый старт

```bash
minikube start
minikube tunnel           # отдельный терминал
cd hw-4 && ./init.sh      # ~7 минут
```

## Доступ к UI

| Сервис | URL |
|---|---|
| Vault UI | http://vault-hw4.local (токен: `root`) |
| RabbitMQ Management | http://rabbitmq-hw4.local |
| RedisInsight | http://redisinsight-hw4.local |

> Требуется `minikube tunnel` и записи в `/etc/hosts` (создаются скриптами).

## CacheManager

```go
cm, err := cache.NewManager()     // читает REDIS_HOST, REDIS_PASSWORD из env

cached, err := cm.Get("weather:Moscow")   // "" если нет
cm.Set("weather:Moscow", data, 5*time.Minute)
exists, err := cm.Exists("weather:Moscow")
```

Логика кэширования в задачах:

```
1. Проверить Redis: cm.Get(key)
2. Есть? → [CACHE HIT] вернуть из кэша
3. Нет?  → [API CALL] вызвать внешний API
        → [CACHE SET] сохранить в Redis с TTL
        → вернуть результат
```

## Полезные команды

```bash
# Поды
kubectl get pods -n k8s-hw4

# Логи consumer-ов (видно CACHE HIT / API CALL)
kubectl logs -f deployment/consumer-weather -n k8s-hw4
kubectl logs -f deployment/consumer-news -n k8s-hw4

# Проверить ключи в Redis
kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass KEYS '*'
kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass GET weather:Moscow
kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass TTL weather:Moscow

# Очистить кэш
kubectl exec redis-0 -n k8s-hw4 -- redis-cli -a redis_secret_pass FLUSHDB
```

## Чеклист для защиты

Пошаговый план демонстрации: **[CHECKLIST.MD](CHECKLIST.MD)**

## Очистка

```bash
./teardown.sh
kubectl delete namespace k8s-hw4
```
