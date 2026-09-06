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
| 7 | Масштабирование | [hw-7/](hw-7/) | metrics-server, requests/limits, стресс-тесты Locust, HPA + VPA, locust-operator |

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

### ДЗ 7: Масштабирование

Go API с PostgreSQL под нагрузкой Locust: от начальных лимитов до автомасштабирования.

- **metrics-server** — addon minikube, источник CPU/RAM для `kubectl top`, HPA и VPA
- **requests/limits** — начальные значения по замерам в покое, новые — по критической точке
- **Locust** — тест на GET-эндпоинты API (`/db/requests`, `/db/report`, `/db/stats`),
  настройки в `locust.conf`, ступенчатый поиск максимума пользователей по CSV-отчётам
- **HPA** — `autoscaling/v2`, CPU 70%, 2–6 реплик, быстро вверх / окно стабилизации 300 с вниз
- **VPA** — чарт Fairwinds, `updateMode: "Off"` (только рекомендации, чтобы не конфликтовать с HPA по CPU)
- **locust-operator** — `LocustTest` + ConfigMap с `locustfile.py` + Ingress на `load-test-v2-webui:8089`
- Изолированный namespace `k8s-hw7`, сборка и деплой через werf + GHCR

Подробнее: [hw-7/README.MD](hw-7/README.MD) | Чеклист для защиты: [hw-7/CHECKLIST.MD](hw-7/CHECKLIST.MD)
