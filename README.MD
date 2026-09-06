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
| 11 | Мониторинг | [hw-11/](hw-11/) | helmfile, Prometheus + метрики ингресса, Loki + promtail, Grafana с алертингом на SMTP |

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

### ДЗ 11: Мониторинг

Стек мониторинга в minikube, развёрнутый одной командой через helmfile:

- **helmfile** — пять релизов декларативно в одном файле: репозитории, пинованные версии чартов, values и порядок установки через `needs`
- **Prometheus** — чарт `kube-prometheus-stack` (Operator + CRD `ServiceMonitor`), Alertmanager, node-exporter, kube-state-metrics
- **Метрики ингресса** — свой мини-чарт `charts/ingress-metrics`: Service на порт 10254 контроллера в namespace `ingress-nginx` + ServiceMonitor в `k8s-hw11`
- **Loki + promtail** — логи всех подов кластера, Loki в режиме SingleBinary на filesystem
- **Grafana** — datasources, дашборды и алертинг целиком через provisioning; contact point на email, SMTP-токен только из Keychain
- Изолированный namespace `k8s-hw11`, идемпотентные `init.sh` / `teardown.sh`

Подробнее: [hw-11/README.MD](hw-11/README.MD) | Чеклист для защиты: [hw-11/CHECKLIST.MD](hw-11/CHECKLIST.MD)
