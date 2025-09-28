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
├── Makefile
├── README.md
├── go.mod / go.sum
├── main.go
├── docker/
│   ├── app.Dockerfile              # образ приложения
│   └── migrations.Dockerfile       # образ миграций (golang-migrate)
├── scripts/
│   ├── gen-dashboard-token.sh
│   └── migrations-entrypoint.sh    # entrypoint миграционного образа
├── migrations/
│   └── 0001_create_requests_table.up.sql
├── docs/
│   ├── swagger.go
│   ├── swagger_embed.go
│   └── swagger.json
├── internal/
│   ├── api/ (meta + responses + server)
│   ├── config/ (envconfig)
│   ├── handler/ (эндпоинты и readiness)
│   └── db/ (pgx pool, без авто-миграций)
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
│       ├── db.yaml
│       ├── migrations-job.yaml     # Job для применения миграций
│       ├── secrets.yaml
│       └── service.yaml
└── bin/ (build артефакты)
```

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

## Примечание по БД
Приложение больше не создаёт таблицы автоматически. Все изменения схемы выполняются через миграционную Kubernetes Job (`k8s-test-backend-migrations`). Если миграции не применены, запрос к `/db/requests` вернёт ошибку уровня БД.

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
make docker VERSION=1.2.3      # образ fastrapier1/k8s-test-backend-app:1.2.3
make docker                    # образ :latest
```
Публикация образа:
```bash
make docker-push VERSION=1.2.3
make docker-push               # push :latest
```
Переменная `IMAGE_REPO` (по умолчанию `fastrapier1/k8s-test-backend-app`) может быть переопределена:
```bash
IMAGE_REPO=myregistry.local:5000/k8s-test-backend-app make docker-push
```
Локальный запуск:
```bash
docker run --rm -p 8080:8080 \
  -e APP_CONFIG_MAP_ENV_VAR=demo \
  fastrapier1/k8s-test-backend-app:latest
```

## Миграции
Образ миграций: `fastrapier1/k8s-test-backend-migrations` (Dockerfile: `docker/migrations.Dockerfile`).
Job: `k8s/db/migrations-job.yaml` (имя Job: `k8s-test-backend-migrations`).

Цели Makefile:
| Цель | Описание |
|------|----------|
| docker-migrations | Сборка образа миграций |
| docker-migrations-push | Push образа миграций |
| migrations-job | Применение миграций в кластере |
| deploy | Полный цикл (оба образа + миграции + приложение) |

Добавление миграции:
1. Создать `migrations/0002_<desc>.up.sql`
2. (Опц.) `0002_<desc>.down.sql`
3. `make docker-migrations-push VERSION=next`
4. `VERSION=next make deploy`

Ручной запуск только миграций:
```bash
make docker-migrations-push
make migrations-job
```

## Kubernetes деплой
```bash
make deploy            # :latest
make deploy VERSION=1.2.3
```
Требования: контекст `docker-desktop`, docker login.

## Readiness
`/readyz`:
1. Прогрев → `503 {"ready":"warming"}`
2. БД (если конфиг задан): `db-connecting` / `db-ping-fail`
3. Готово → `200 {"ready":"true"}`

## Работа с PVC
- Динамический провижининг (default StorageClass)
- Общая PVC для всех реплик Deployment

## Очистка
```bash
make clean
```