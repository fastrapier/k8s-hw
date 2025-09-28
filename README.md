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

## Структура
```
.
├── main.go
├── internal/
│   └── api/
│       ├── server.go
│       ├── responses.go
│       ├── swagger_embed.go
│       ├── swagger.json         # генерируется goswagger'ом (заглушка в репо)
│       └── doc.go
├── scripts/
│   └── gen-dashboard-token.sh
├── k8s/
│   ├── namespace.yaml
│   ├── pvc.yaml                 # динамический PVC (default StorageClass)
│   └── app/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── secret.yaml
│       └── config-map.yaml
├── Makefile
├── Dockerfile
├── go.mod / go.sum
└── README.md
```

(Статический `pv.yaml` удалён: теперь используется динамический провижининг через default StorageClass кластера `docker-desktop`).

## Требования
- Go 1.21+
- `kubectl` (для `make dashboard-token` и деплоя)
- Docker (сборка образа)
- Kubernetes кластер (ожидается контекст `docker-desktop`)

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

## Маршруты
| Метод | Путь | Описание |
|-------|------|----------|
| GET | / | Приветствие |
| GET | /healthz | Liveness |
| GET | /readyz | Readiness |
| GET | /version | Версия сервиса |
| GET | /test-env | Значение из ConfigMap env |
| GET | /secret | Маскированные секреты |
| POST | /pvc-test | Создать файл в PVC (опц. `?name=`) |
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

## Быстрый старт (локально)
```bash
make run
```

С переменными:
```bash
APP_PORT=9090 APP_CONFIG_MAP_ENV_VAR="hello" make run
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
make build
make docker          # соберёт образ с VERSION=latest
VERSION=1.2.3 make docker
```
Запуск образа:
```bash
docker run --rm -p 8080:8080 -e APP_CONFIG_MAP_ENV_VAR=demo k8s-hw:latest
```

## Kubernetes деплой (dynamic PVC)
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/app/secret.yaml
kubectl apply -f k8s/app/config-map.yaml
kubectl apply -f k8s/app/deployment.yaml
kubectl apply -f k8s/app/service.yaml
```
Проверить:
```bash
kubectl get pods -n k8s-hw -l app=k8s-test-backend-app
kubectl exec -n k8s-hw deploy/k8s-test-backend-app -- curl -s -X POST http://localhost:8080/pvc-test
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
`/readyz` возвращает 503 пока не истёк интервал `APP_READINESS_WARMUP_SECONDS`.

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
