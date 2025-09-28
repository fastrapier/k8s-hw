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

## Структура
```
.
├── main.go
├── internal/
│   └── api/
│       ├── server.go
│       ├── responses.go
│       ├── swagger_embed.go
│       ├── swagger.json        # генерируется goswagger'ом (заглушка в репо)
│       └── doc.go
├── scripts/
│   └── gen-dashboard-token.sh  # генерация токена для Kubernetes Dashboard
├── k8s/                        # k8s манифесты
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── nam.yaml
│   └── pv.yaml
├── Makefile
├── Dockerfile
├── go.mod / go.sum
└── README.md
```

## Требования
- Go 1.21+
- `kubectl` (для `make dashboard-token`)
- Docker (для сборки образа)

## Конфигурация через переменные окружения (префикс APP_)
| Переменная | Назначение | Значение по умолчанию |
|-----------|------------|-----------------------|
| APP_PORT | Порт HTTP | 8080 |
| APP_READINESS_WARMUP_SECONDS | Время (сек) до готовности (/readyz) | 1 |
| APP_SHUTDOWN_TIMEOUT_SECONDS | Таймаут graceful shutdown (сек) | 10 |
| APP_CONFIG_MAP_ENV_VAR | Значение, выдаваемое в /test-env | (пусто) |

## Быстрый старт (локально)
```bash
make run
```
Маршруты:
- /healthz
- /readyz
- /version
- /test-env
- /swagger
- /swagger.json

Пример с переменными:
```bash
APP_PORT=9090 APP_CONFIG_MAP_ENV_VAR="hello" make run
```

## Kubernetes Dashboard (токен)
Получить токен для входа:
```bash
make dashboard-token
```
Условие: текущий контекст kubectl = docker-desktop.
Скрипт создаёт (при необходимости) ServiceAccount, ClusterRoleBinding и Secret с долговечным токеном. Выведите токен ещё раз повторным запуском команды.

## Swagger
```bash
make swagger   # регенерация swagger.json
```
Swagger генерируется автоматически перед build/test.

## Тесты
```bash
make test
```

## Сборка / Docker
```bash
make build
VERSION=1.2.3 make build
make docker
VERSION=1.2.3 make docker
```
Запуск образа:
```bash
docker run --rm -p 8080:8080 -e APP_CONFIG_MAP_ENV_VAR=demo app:latest
```

## Graceful shutdown
Пример:
```bash
make run &
kill -TERM <pid>
```
Сервер корректно завершается за таймаут `APP_SHUTDOWN_TIMEOUT_SECONDS`.

## Версия через ldflags
Используется:
```
-X k8s-hw/internal/api.Version=<value>
```

## Readiness
`/readyz` возвращает 503 пока не истёк интервал `APP_READINESS_WARMUP_SECONDS`.

## Очистка
```bash
make clean
```
