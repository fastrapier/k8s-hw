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
├── main.go                     # точка входа (только запуск сервера)
├── internal/api/               # вся логика HTTP и swagger описания
│   ├── server.go               # хэндлеры, маршруты, версия
│   ├── responses.go            # swagger:response структуры
│   ├── swagger_embed.go        # embed swagger.json
│   ├── swagger.json            # генерируется (перезаписывается) goswagger'ом
│   └── doc.go                  # swagger:meta
├── Makefile
├── Dockerfile
├── config-map/                 # доп. артефакты (если нужны для k8s)
├── k8s/                        # манифесты k8s (если есть)
└── go.mod / go.sum
```

## Требования
- Go 1.21+ (указан 1.24 в go.mod/toolchain — гибко под адаптацию)
- Установленный `goswagger` (Makefile сам установит при первом вызове `make swagger`)

## Конфигурация через переменные окружения (префикс APP_)
| Переменная | Назначение | Значение по умолчанию |
|-----------|------------|-----------------------|
| APP_PORT | Порт HTTP | 8080 |
| APP_READINESS_WARMUP_SECONDS | Время (сек) до готовности (/readyz) | 1 |
| APP_SHUTDOWN_TIMEOUT_SECONDS | Таймаут graceful shutdown (сек) | 10 |
| APP_CONFIG_MAP_ENV_VAR | Значение, выдаваемое в /test-env | (пусто) |

## Быстрый старт (локально)
Собрать и запустить:
```bash
make run
```
Открыть:
- http://localhost:8080/          — приветствие
- http://localhost:8080/healthz   — liveness
- http://localhost:8080/readyz    — readiness
- http://localhost:8080/version   — версия
- http://localhost:8080/test-env  — значение `APP_CONFIG_MAP_ENV_VAR`
- http://localhost:8080/swagger   — Swagger UI
- http://localhost:8080/swagger.json — спецификация

С кастомными переменными окружения:
```bash
APP_PORT=9090 \
APP_READINESS_WARMUP_SECONDS=5 \
APP_CONFIG_MAP_ENV_VAR="hello from config" \
make run
```

## Генерация Swagger вручную
```bash
make swagger
```
(Файл затем встраивается при сборке.
Если нужно обновить — меняйте аннотации и повторяйте `make swagger`.)

## Тесты
```bash
make test
```
Вывод включает генерацию swagger перед тестами.

## Сборка
```bash
make build            # бинарь bin/app
VERSION=1.2.3 make build
```

## Docker
Собрать образ:
```bash
make docker                   # VERSION=dev (по умолчанию)
VERSION=1.2.3 make docker     # c конкретной версией
```
Запуск контейнера:
```bash
docker run --rm -p 8080:8080 \
  -e APP_CONFIG_MAP_ENV_VAR=demo \
  app:1.2.3
```

## Graceful shutdown пример
```bash
make run &
kill -TERM <pid>
```
(В логе появится сообщение об остановке.)

## Версия
ldflags:
```
-X k8s-hw/internal/api.Version=<value>
```
Меняется через переменную VERSION в make / docker.

## Readiness логика
`/readyz` возвращает 503 (warming) пока не истёк интервал `APP_READINESS_WARMUP_SECONDS`.

## Идеи для расширения
- `/metrics` (Prometheus)
- `golangci-lint` + CI
- Helm chart
- Middleware (логирование, trace, rate limiting)

## Очистка
```bash
make clean
```

---
Сообщите, если требуется добавить CI, метрики или другие функции.
