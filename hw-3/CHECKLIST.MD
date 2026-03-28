# Чеклист для защиты ДЗ 3

## Подготовка (до экзамена)

```bash
minikube start
minikube tunnel        # в отдельном терминале, не закрывать
cd hw-3 && ./init.sh   # ждём ~5 минут
```

Убедиться что всё поднялось:

```bash
kubectl get pods -n k8s-hw
```

Все поды должны быть `Running` (producer-ы — `Completed`).

---

## Порядок демонстрации

### 1. Инфраструктура

- [ ] Показать что всё запущено:
  ```bash
  kubectl get pods -n k8s-hw
  kubectl get cronjob -n k8s-hw
  kubectl get svc -n k8s-hw
  kubectl get ingress -n k8s-hw
  ```

### 2. Vault (секреты и AppRole)

- [ ] Открыть Vault UI: http://vault.local (токен `root`)
- [ ] Показать секреты: `secret/rabbitmq`, `secret/weather`, `secret/news`
- [ ] Показать политики: `app-policy`, `rabbitmq-policy`
- [ ] Показать AppRole:
  ```bash
  kubectl exec vault-0 -n k8s-hw -- vault read auth/approle/role/app-role
  ```
- [ ] Объяснить: «AppRole позволяет приложениям получать временные токены вместо root-токена. Приложение получает role_id и secret_id, обменивает их на временный токен с ограниченными правами»

### 3. RabbitMQ (Часть 1)

- [ ] Открыть RabbitMQ Management: http://rabbitmq.local
- [ ] Показать очереди: `weather`, `news`, `celery` (вкладка Queues)
- [ ] Показать exchange `api_tasks` (вкладка Exchanges → api_tasks → Bindings)
- [ ] Объяснить: «Аутентификация через helm-secrets/vals — логин/пароль подтягиваются из Vault при деплое, не хардкодятся в values»

### 4. Go Producer/Consumer (Часть 2)

- [ ] Показать логи consumer-ов (данные обновляются каждую минуту):
  ```bash
  kubectl logs deployment/consumer-weather -n k8s-hw --tail=10
  kubectl logs deployment/consumer-news -n k8s-hw --tail=10
  ```
  Ожидаемый вывод — температура в Москве, заголовки новостей.

- [ ] Показать CronJob-ы и их Jobs:
  ```bash
  kubectl get cronjob -n k8s-hw
  kubectl get jobs -n k8s-hw -l app=producer
  ```

- [ ] Показать код: `go/cmd/producer/main.go`, `go/cmd/consumer/main.go`

- [ ] Ключевые моменты для объяснения:
  - Producer создаёт **durable direct exchange** `api_tasks`
  - Отправляет **durable-сообщение** с routing key (`weather`/`news`)
  - Consumer принимает очередь из CLI (`--queue weather`)
  - Создаёт **durable-очередь** и **биндит к exchange**
  - После обработки отправляет **ACK** (manual acknowledgement)
  - Оба получают credentials из **Vault через AppRole**

### 5. Celery + Flower (Часть 3)

- [ ] Показать Celery worker:
  ```bash
  kubectl logs deployment/celery-worker -n k8s-hw --tail=10
  ```

- [ ] Открыть Flower: http://flower.local

- [ ] Показать конфигурацию: `celery/app/celeryconfig.py`, `celery/app/celery_app.py`

- [ ] Ключевые моменты:
  - `celeryconfig.py` — broker_url из переменных окружения (K8s Secret `celery-broker`)
  - Celery worker подключается к тому же RabbitMQ, но через отдельную очередь `celery`
  - Flower — готовый инструмент мониторинга, показывает задачи, воркеры, статистику

### 6. FastAPI + Celery задачи (Часть 4)

- [ ] Открыть Swagger UI: http://celery-api.local/docs

- [ ] Отправить задачу на погоду:
  ```bash
  curl -s -X POST 'http://celery-api.local/tasks/weather?city=Moscow' | jq
  ```
  Ответ: `{"task_id": "...", "status": "PENDING"}`

- [ ] Проверить статус (подставить task_id из ответа):
  ```bash
  curl -s http://celery-api.local/tasks/TASK_ID | jq
  ```
  Ответ: `{"task_id": "...", "status": "SUCCESS", "result": {"city": "Moscow", "temp": 14.2, ...}}`

- [ ] Отправить задачу на новости:
  ```bash
  curl -s -X POST 'http://celery-api.local/tasks/news?q=kubernetes' | jq
  ```

- [ ] Проверить статус:
  ```bash
  curl -s http://celery-api.local/tasks/TASK_ID | jq
  ```

- [ ] Показать в Flower (http://flower.local) что задачи выполнены

- [ ] Показать код: `celery/app/tasks.py`, `celery/app/api.py`

- [ ] Ключевые моменты:
  - `POST /tasks/weather` вызывает `fetch_weather.delay(city)` — ставит задачу в очередь
  - `GET /tasks/{task_id}` использует `AsyncResult` для получения статуса
  - Задачи получают API-ключи из Vault через AppRole (тот же механизм что и Go)

### 7. Сборка и деплой (werf + GHCR)

- [ ] Показать `go/werf.yaml` (Go) и `celery/werf.yaml` (Python)
- [ ] Показать Helm-чарты: `go/.helm/templates/`, `celery/.helm/templates/`
- [ ] Объяснить: «werf собирает образы, пушит в ghcr.io, деплоит через Helm. Два отдельных werf-проекта в `go/` и `celery/`, каждый со своим werf.yaml и Helm-чартом»

### 8. Идемпотентность и очистка

- [ ] Объяснить: «`init.sh` идемпотентный — можно запускать повторно без побочных эффектов. Все секреты создаются через `--dry-run=client | kubectl apply`, Helm использует `upgrade --install`»
- [ ] Показать `teardown.sh` — полная очистка всех ресурсов

---

## Быстрые команды (шпаргалка)

```bash
# Всё поднять
./init.sh

# Логи Go consumer-ов
kubectl logs -f deployment/consumer-weather -n k8s-hw
kubectl logs -f deployment/consumer-news -n k8s-hw

# Логи Celery
kubectl logs -f deployment/celery-worker -n k8s-hw

# Очереди RabbitMQ
kubectl exec rabbitmq-0 -n k8s-hw -- rabbitmqctl list_queues name messages consumers

# Celery задачи через API
curl -s -X POST 'http://celery-api.local/tasks/weather?city=Moscow' | jq
curl -s -X POST 'http://celery-api.local/tasks/news?q=kubernetes' | jq
curl -s http://celery-api.local/tasks/TASK_ID | jq

# Flower
open http://flower.local

# Всё удалить
./teardown.sh
```
