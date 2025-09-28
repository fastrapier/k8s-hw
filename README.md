# k8s-hw

Минимальный HTTP сервис на Go со следующими возможностями:
- Стандартный net/http
- Graceful shutdown (SIGINT/SIGTERM)
- Liveness `/healthz` и Readiness `/readyz` ("warming" первую секунду / настраивается)
- Версия приложения `/version` (через ldflags + версия Go runtime)
- Отдача значения переменной окружения `/test-env`
- Автогенерация Swagger спецификации (goswagger) + `/swagger.json` + встроенный Swagger UI `/swagger`
- Multi-stage Docker image (финальный бинарь `app` под non-root пользователем)
- Встраивание (embed) swagger.json (через go:embed)
- Unit-тесты для основных эндпоинтов
- Конфигурация через env (префикс `APP_`)
- Работа с Kubernetes Secret (`/secret`, маскированный пароль)
- Запись тестового файла в PVC: POST `/pvc-test` (создаёт файл; имя включает pod name при нескольких репликах)
- Подключение к Postgres и запись отметки запроса: POST `/db/requests`

## Структура
```
.
├── Dockerfile
├── Makefile
├── README.md
├── go.mod
├── go.sum
├── main.go
├── docs/
│   ├── swagger.go            # отдача swagger.json и UI хендлеры
│   ├── swagger_embed.go      # embed swagger.json
│   └── swagger.json          # генерируется (заглушка в репо / перегенерируется make swagger)
├── internal/
│   ├── api/
│   │   ├── meta.go           # swagger:meta + общая информация
│   │   ├── responses.go      # структуры swagger:response
│   │   └── server.go         # сборка http.ServeMux
│   ├── config/
│   │   └── config.go         # загрузка env (envconfig)
│   ├── handler/
│   │   ├── base.go           # hello/version/db insert
│   │   ├── cfg.go            # InitConfig, глобальные параметры
│   │   ├── db.go             # InsertRequest handler
│   │   ├── healthcheck.go    # /healthz /readyz
│   │   ├── pvc.go            # /pvc-test
│   │   └── secrets.go        # /secret
│   └── db/
│       └── db.go             # pgx pool, миграция (таблица requests)
├── k8s/
│   ├── namespace.yaml
│   ├── pvc.yaml
│   ├── app/
│   │   ├── config-map.yaml
│   │   ├── deployment.yaml
│   │   ├── secret.yaml
│   │   └── service.yaml
│   └── db/
│       ├── config-map.yaml
│       ├── db.yaml           # StatefulSet Postgres
│       ├── secrets.yaml
│       └── service.yaml
├── scripts/
│   └── gen-dashboard-token.sh
└── bin/                      # (генерируется) бинарь после make build
```

(Статический pv удалён: используется динамический PVC.)

## Требования
- Go 1.21+
- `kubectl` (для `make dashboard-token` и деплоя)
- Docker (сборка образа)
- Kubernetes кластер (ожидается контекст `docker-desktop`)
- (Опционально) Postgres доступный из Pod (см. k8s/db/* манифесты)

## Конфигурация через переменные окружения (префикс APP_)
| Переменная | Назначение | Значение по умолчанию |
|-----------|------------|-----------------------|
| APP_PORT | Порт HTTP | 8080 |
| APP_READINESS_WARMUP_SECONDS | Время (сек) до готовности (/readyz) | 1 |
| APP_SHUTDOWN_TIMEOUT_SECONDS | Таймаут graceful shutdown (сек) | 10 |
| APP_CONFIG_MAP_ENV_VAR | Значение, выдаваемое в /test-env | (пусто) |
| APP_DATA_DIR | Каталог для данных / PVC | /var/lib/k8s-test-backend/data |
| APP_POD_NAME | Имя пода (в Kubernetes через Downward API) | (пусто) |
| APP_SECRET_USERNAME | Имя пользователя (из Secret) | (пусто) |
| APP_SECRET_PASSWORD | Пароль (из Secret) | (пусто) |
| APP_POSTGRES_HOST | Хост Postgres | localhost |
| APP_POSTGRES_PORT | Порт Postgres | 5432 |
| APP_POSTGRES_USER | Пользователь Postgres | (пусто) |
| APP_POSTGRES_PASSWORD | Пароль Postgres | (пусто) |
| APP_POSTGRES_DB | Имя БД | (пусто) |

При старте сервис создаёт (idempotent) таблицу `requests`:
```sql
CREATE TABLE IF NOT EXISTS requests(
  id BIGSERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## Маршруты
| Метод | Путь | Описание |
|-------|------|----------|
| GET | / | Приветствие |
| GET | /healthz | Liveness |
| GET | /readyz | Readiness (прогрев + ожидание БД если настроена) |
| GET | /version | Версия сервиса |
| GET | /test-env | Значение из ConfigMap env |
| GET | /secret | Маскированные секреты |
| POST | /pvc-test | Создать файл в PVC (опц. `?name=`) |
| POST | /db/requests | Создать запись в Postgres (timestamp) |
| GET | /swagger | Swagger UI |
| GET | /swagger.json | Swagger спецификация |

### Пример `/pvc-test`
```
curl -X POST http://localhost:8080/pvc-test
curl -X POST "http://localhost:8080/pvc-test?name=myfile.txt"
```
Ответ (пример):
```json
{
  "file": "k8s-test-backend-app-6d9c48b6d9-x7kq2-1738143273123456789.txt",
  "path": "/var/lib/k8s-test-backend/data/k8s-test-backend-app-6d9c48b6d9-x7kq2-...txt",
  "sizeBytes": 54,
  "podName": "k8s-test-backend-app-6d9c48b6d9-x7kq2"
}
```

### Пример `/db/requests`
```
curl -X POST http://localhost:8080/db/requests
```
Ответ (пример):
```json
{
  "id": 42,
  "createdAt": "2025-09-28T10:15:20.123456Z"
}
```
Ошибки:
- `503 {"error":"db client not initialized"}` — если не сконфигурирован Postgres.
- `500` — внутренняя ошибка вставки.

## Быстрый старт (локально)
```bash
make run
```

Для локальной проверки Postgres (при наличии docker):
```bash
docker run --rm -e POSTGRES_PASSWORD=pass -e POSTGRES_USER=user -e POSTGRES_DB=dev -p 5432:5432 postgres:16
APP_POSTGRES_HOST=127.0.0.1 APP_POSTGRES_USER=user APP_POSTGRES_PASSWORD=pass APP_POSTGRES_DB=dev make run
```

## Swagger
```bash
make swagger   # регенерация swagger.json
```
Swagger генерируется автоматически перед build/test (через таргеты Makefile).

## Тесты
```bash
make test
```

## Сборка / Docker
```bash
make build                     # локальная сборка бинаря
make docker VERSION=1.2.3      # соберёт образ fastrapier1/k8s-test-backend-app:1.2.3
make docker                    # соберёт образ с тегом :latest
```
Публикация образа в Docker Hub (нужен `docker login`):
```bash
make docker-push VERSION=1.2.3
make docker-push               # push :latest
```
Переменная `IMAGE_REPO` (по умолчанию `fastrapier1/k8s-test-backend-app`) может быть переопределена:
```bash
IMAGE_REPO=myregistry.local:5000/k8s-test-backend-app make docker-push
```
Локальный запуск собранного образа:
```bash
docker run --rm -p 8080:8080 \
  -e APP_CONFIG_MAP_ENV_VAR=demo \
  fastrapier1/k8s-test-backend-app:latest
```

## Kubernetes деплой (dynamic PVC + удалённый образ)
Полный цикл (сборка, push, применение манифестов, rollout):
```bash
make deploy                    # использует :latest
make deploy VERSION=1.2.3      # использует тег 1.2.3
```
Требования:
- kubectl context = docker-desktop (Makefile проверяет)
- Выполнен `docker login` для репозитория `fastrapier1`

Под капотом `make deploy` выполняет:
1. `make docker` (сборка) → `make docker-push` (push образа)
2. `kubectl apply` всех манифестов (`k8s/namespace.yaml`, `k8s/db`, `k8s/pvc.yaml`, `k8s/app`)
3. `kubectl set image` для `Deployment/k8s-test-backend-app`
4. Ожидает rollout (`kubectl rollout status`)

Проверка:
```bash
kubectl get pods -n k8s-hw -l app=k8s-test-backend-app
kubectl logs -n k8s-hw deploy/k8s-test-backend-app | head
```
Удаление ресурсов:
```bash
make undeploy
```

## Получение токена для Kubernetes Dashboard
```bash
make dashboard-token
```
(Контекст kubectl должен быть `docker-desktop`). Токен долговечный, можно получить повторно.

## Graceful shutdown
```bash
make run &
PID=$!
kill -TERM $PID
wait $PID
```

## Версия через ldflags
Флаг линковки:
```
-X k8s-hw/internal/api.VersionHandler=<value>
```

## Readiness
`/readyz` теперь учитывает:
1. Интервал прогрева (`APP_READINESS_WARMUP_SECONDS`). Пока не прошёл — `503 {"ready":"warming"}`.
2. Если заданы переменные `APP_POSTGRES_HOST`, `APP_POSTGRES_USER`, `APP_POSTGRES_DB` (и опц. пароль) — сервис считает, что БД обязательна для готовности и:
   - Лениво инициализирует подключение только при первом /readyz после прогрева.
   - Если соединение/миграция ещё не прошли — `503 {"ready":"db-connecting"}`.
   - Если подключение есть, но `Ping` неуспешен — `503 {"ready":"db-ping-fail"}`.
3. Когда всё готово — `200 {"ready":"true"}`.

Благодаря ленивой инициализации и повторным попыткам readiness не возвращает 200 пока DNS для Postgres не начнёт резолвиться и сам Postgres не станет доступен.

### Возможные статусы `/readyz`
| Статус JSON | HTTP | Значение |
|-------------|------|----------|
| {"ready":"warming"} | 503 | Ещё не истёк прогрев. |
| {"ready":"db-connecting"} | 503 | Пытаемся создать пул + миграция таблицы `requests`. |
| {"ready":"db-ping-fail"} | 503 | Пул создан, но `Ping` не прошёл (сетевые/DNS/несанкционирован). |
| {"ready":"true"} | 200 | Сервис готов (и БД доступна если требовалась). |

### Поведение при неуказанной БД
Если отсутствуют обязательные поля (host/user/db), БД считается «необязательной» и readiness после прогрева сразу станет 200.

### Почему это важно для headless Service
Headless Service для Postgres может давать NXDOMAIN до появления Endpoints. Теперь приложение:
- Не падает при старте на ошибке DNS (нет ранней обязательной инициализации).
- Продолжает возвращать 503 пока DNS/Pod не готовы, обеспечивая корректный rollout в Kubernetes.

## Работа с PVC
- Используется динамический провижининг (default StorageClass в кластере; в Docker Desktop обычно `docker-desktop`).
- Одна PVC разделяется всеми репликами Deployment (race conditions допустимы для теста).
- Для изолированного хранения на реплику — перейти на StatefulSet и volumeClaimTemplates.

## Очистка
```bash
make clean
```

## Дальнейшие возможные улучшения
- StatefulSet для уникального хранилища на под
- Endpoint для листинга/удаления файлов в PVC
- Prometheus метрики / ротация логов
- CI workflow (lint/test/build/push)
