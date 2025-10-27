# k8s-hw

Минимальный HTTP сервис на Go + демонстрация Kubernetes (Deployment, StatefulSet Postgres, PVC, CronJob, Ingress с HTTPS) со следующими возможностями:
- Стандартный net/http
- Graceful shutdown (SIGINT/SIGTERM)
- Liveness `/healthz` и Readiness `/readyz` ("warming" первую секунду / настраивается)
- Версия приложения `/version` (через ldflags + версия Go runtime)
- Отдача значения переменной окружения `/test-env`
- Автогенерация Swagger спецификации (go-swagger) + `/swagger.json` + встроенный Swagger UI `/swagger` (schemes: http, https)
- Multi-stage Docker image (финальный бинарь под non-root)
- Встраивание (embed) swagger.json (go:embed)
- Unit-тесты для основных эндпоинтов
- Конфигурация через env (префикс `APP_`)
- Работа с Kubernetes Secret (`/secret`, маскирование пароля)
- Запись тестового файла в PVC: POST `/pvc-test` (имя включает Pod name)
- Подключение к Postgres и запись отметки запроса: POST `/db/requests`
- Отдельный образ миграций + Kubernetes Job для миграций
- CronJob (каждую минуту) — вставляет запись в таблицу `cron_runs`
- Ingress + auto self‑signed TLS (доступ: `https://k8s-hw.local`)
- Авто генерация / удаление локального самоподписанного сертификата (создаётся при deploy, удаляется при undeploy)

> Пример учебный, не прод: self-signed TLS, отсутствует авто‑rotate секрета, нет продового hardening.

## Структура
```
.
├── Makefile
├── README.md
├── go.mod / go.sum
├── main.go
├── certs/                     # (создаётся при deploy: tls.key/tls.crt; очищается при undeploy)
├── docker/
│   ├── app.Dockerfile         # образ приложения
│   ├── migrations.Dockerfile  # образ миграций (golang-migrate)
│   └── cron.Dockerfile        # образ для CronJob
├── cmd/
│   └── cronjob/main.go        # код CronJob (один запуск -> INSERT в cron_runs)
├── scripts/
│   ├── gen-dashboard-token.sh
│   └── migrations-entrypoint.sh
├── migrations/
│   ├── 0001_create_requests_table.up.sql
│   └── 0002_create_cron_runs_table.up.sql
├── docs/
│   ├── swagger.go
│   ├── swagger_embed.go
│   └── swagger.json
├── internal/
│   ├── api/
│   ├── config/
│   ├── handler/
│   └── db/
├── k8s/
│   ├── namespace.yaml
│   ├── pvc.yaml                # PVC для приложения
│   ├── app/
│   │   ├── config-map.yaml
│   │   ├── secret.yaml
│   │   ├── service.yaml
│   │   ├── deployment.yaml
│   │   ├── cronjob.yaml        # CronJob (*/1 * * * *)
│   │   └── ingress.yaml        # Ingress + TLS
│   └── db/
│       ├── config-map.yaml
│       ├── secrets.yaml
│       ├── service.yaml        # headless + обычный + nodePort
│       ├── db.yaml             # StatefulSet (реплики: 2)
│       └── migrations-job.yaml # Job миграций
└── bin/ (build артефакты)
```

## Переменные окружения (префикс APP_)
| Переменная | Назначение | По умолчанию |
|-----------|------------|--------------|
| APP_PORT | Порт HTTP | 8080 |
| APP_READINESS_WARMUP_SECONDS | Прогрев (`warming`) | 1 |
| APP_SHUTDOWN_TIMEOUT_SECONDS | Graceful shutdown | 10 |
| APP_CONFIG_MAP_ENV_VAR | Значение для `/test-env` | (пусто) |
| APP_DATA_DIR | Каталог для PVC | /var/lib/k8s-test-backend/data |
| APP_POD_NAME | Имя пода (Downward API) | (пусто) |
| APP_SECRET_USERNAME | Пользователь (Secret) | (пусто) |
| APP_SECRET_PASSWORD | Пароль (Secret) | (пусто) |
| APP_POSTGRES_HOST | Хост Postgres | localhost |
| APP_POSTGRES_PORT | Порт Postgres | 5432 |
| APP_POSTGRES_USER | Пользователь | (пусто) |
| APP_POSTGRES_PASSWORD | Пароль | (пусто) |
| APP_POSTGRES_DB | БД | (пусто) |

## База данных / миграции
- Авто‑создание схемы приложением отсутствует.
- Все изменения в `migrations/` => образ миграций => Job (`migrations-job`).
- Таблицы: `requests`, `cron_runs` (вторая наполняется CronJob'ом).
- Порядок при deploy: Postgres StatefulSet -> миграции -> приложение -> CronJob.

### Helm-чарты
Проект содержит полноценные Helm-чарты для развёртывания приложения.

#### Основной чарт (umbrella chart)
В каталоге `helm/app/` находится основной Helm-чарт, который включает в себя два subchart'а:
- `postgres` — PostgreSQL StatefulSet с конфигурацией и секретами
- `backend` — приложение с Deployment, CronJob, миграциями и Ingress

**Структура:**
```
helm/app/
├── Chart.yaml              # метаданные и зависимости
├── values.yaml             # конфигурация верхнего уровня
├── templates/
│   └── _helpers.tpl
└── charts/
    ├── backend/            # subchart для приложения
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/      # deployment, service, cronjob, migrations, etc.
    └── postgres/           # subchart для БД
        ├── Chart.yaml
        ├── values.yaml
        └── templates/      # statefulset, services, secrets, configmap
```

**Проверка чарта:**
```bash
make helm-lint
# или
helm lint helm/app/
```

**Предпросмотр манифестов:**
```bash
make helm-template
# или
helm template k8s-hw-app helm/app/ --namespace k8s-hw
```

**Установка через Helm:**
```bash
make helm-install
# или
helm install k8s-hw-app helm/app/ -n k8s-hw --create-namespace
```

**Обновление:**
```bash
make helm-upgrade VERSION=1.2.3
# или
helm upgrade k8s-hw-app helm/app/ -n k8s-hw \
  --set backend.images.backend.tag=1.2.3 \
  --set backend.images.migrations.tag=1.2.3 \
  --set backend.images.cron.tag=1.2.3
```

**Удаление:**
```bash
make helm-uninstall
# или
helm uninstall k8s-hw-app -n k8s-hw
```

**Примечания:**
- Команда `make deploy` использует прямые манифесты из `k8s/`, а не Helm-чарты
- Для деплоя через Helm используйте `make helm-deploy` (алиас для `helm-install`)
- Helm-чарты автоматически создают все необходимые ресурсы, включая namespace
- Backend subchart автоматически ссылается на PostgreSQL secrets и configmap
- Версии образов можно переопределить через параметр `VERSION` или `--set`

#### Конфигурация subchart'ов

**Backend (helm/app/charts/backend/values.yaml):**
- Настройки приложения (порты, реплики, образы)
- Собственные secrets и configmap для приложения
- Ссылки на PostgreSQL resources через `postgres.configmapName` и `postgres.secretName`
- Поддержка Deployment, CronJob, миграций и Ingress

**PostgreSQL (helm/app/charts/postgres/values.yaml):**
- Настройки БД (пользователь, пароль, база данных)
- Конфигурация StatefulSet (реплики, образ, PVC)
- Создание трёх типов сервисов (headless, ClusterIP, NodePort)

## CronJob
`k8s/app/cronjob.yaml` выполняется каждую минуту (`*/1 * * * *`):
- Стартует контейнер из образа `fastrapier1/k8s-test-backend-cron:<VERSION>`
- Подключается к БД (используя те же секреты/configmap) и вставляет строку в `cron_runs`.
- Логи можно посмотреть: `kubectl logs job/<generated-cronjob-run> -n k8s-hw`.

## HTTPS (Ingress + self-signed)
- При `make deploy`:
  1. Если нет локальных `certs/tls.key` / `certs/tls.crt` — генерируется самоподписанный сертификат (CN=`k8s-hw.local`).
  2. Создаётся (если отсутствует) secret `k8s-hw-tls`.
  3. Применяется `ingress.yaml` с TLS.
- Доступ: `https://k8s-hw.local/` (строка добавляется в `/etc/hosts`).
- При `make undeploy` секрет и локальные файлы сертификата удаляются.
- Для доверия (опционально) можно импортировать `certs/tls.crt` в System Keychain (macOS) / доверенные корни.

## Маршруты
| Метод | Путь | Описание |
|-------|------|----------|
| GET | / | Приветствие |
| GET | /healthz | Liveness |
| GET | /readyz | Readiness (прогрев + БД) |
| GET | /version | Версия |
| GET | /test-env | Значение из ConfigMap |
| GET | /secret | Секреты (маскированы) |
| POST | /pvc-test | Создать файл в PVC (опц. `?name=`) |
| POST | /db/requests | Вставка записи в БД |
| GET | /swagger | Swagger UI |
| GET | /swagger.json | Swagger спецификация |

### Пример `/db/requests`
```bash
curl -X POST http://localhost:8080/db/requests
```

### Пример `/pvc-test`
```bash
curl -X POST http://localhost:8080/pvc-test
```

## Быстрый старт (локально)
```bash
make run
```
Postgres (локальный docker):
```bash
docker run --rm -e POSTGRES_PASSWORD=pass -e POSTGRES_USER=user -e POSTGRES_DB=dev -p 5432:5432 postgres:17
APP_POSTGRES_HOST=127.0.0.1 \
APP_POSTGRES_USER=user \
APP_POSTGRES_PASSWORD=pass \
APP_POSTGRES_DB=dev \
make run
```

## Swagger
```bash
make swagger   # регенерация docs/swagger.json
```
Swagger автоматически строится в целях `build`, `test`, `docker`.

## Тесты
```bash
make test
```

## Docker
```bash
make docker                # build :latest
make docker VERSION=1.2.3  # build с тегом
make docker-push           # push :latest
make docker-push VERSION=1.2.3
```
Переменные можно переопределить: `IMAGE_REPO=... make docker-push`.

## Миграции / Cron образы
| Цель | Описание |
|------|----------|
| docker-migrations | Сборка образа миграций |
| docker-migrations-push | Публикация образа миграций |
| docker-cron | Сборка образа CronJob |
| docker-cron-push | Публикация образа CronJob |
| migrations-job | (Пере)запуск Job миграций (с ожиданием выполнения) |

Добавление миграции:
1. Создать файл `migrations/000X_<desc>.up.sql`
2. (Опц.) down файл
3. `make docker-migrations-push VERSION=<v>`
4. `VERSION=<v> make deploy`

Ручной запуск миграций без полного deploy:
```bash
make docker-migrations-push
make migrations-job
```

## Kubernetes деплой
```bash
make deploy                 # деплой (latest)
make deploy VERSION=1.2.3   # деплой с тегом
```
Шаги внутри (упрощённо): namespace -> Postgres -> PVC -> миграции -> приложение -> CronJob -> cert -> ingress -> вывод pod'ов.

После деплоя:
```bash
curl -k -H 'Host: k8s-hw.local' https://127.0.0.1/healthz
```
(Флаг `-k` из-за self-signed; можно импортировать certs/tls.crt и убрать `-k`).

## Readiness логика
`/readyz` возвращает статусы:
- `warming` — ещё идёт прогрев
- `db-connecting` / `db-ping-fail` — проблемы с БД
- `true` — готово

## PVC
- Один PVC `k8s-test-backend-pvc` монтируется в Deployment
- Файлы создаются через POST `/pvc-test`

## Ingress / HTTPS
Повторно: автоматическая генерация сертификата при `deploy`, удаление при `undeploy`.

## Очистка / Удаление
```bash
make undeploy       # удаляет всё в ns k8s-hw + секрет TLS + локальные certs
make undeploy-full  # дополнительно удаляет namespace ingress-nginx
make clean          # локальные бинарь + swagger.json
```

## Kubernetes Dashboard
Для мониторинга и управления кластером через веб-интерфейс:

### Установка Dashboard
```bash
make dashboard-install
```

### Доступ к Dashboard
1. Запустите прокси (в отдельном терминале):
```bash
make dashboard-proxy
```

2. Получите URL для доступа:
```bash
make dashboard-url
```
Или откройте в браузере:
```
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

3. Получите токен для входа:
```bash
make dashboard-token
```

4. Скопируйте токен и вставьте на странице входа в Dashboard

**Важно:** Не пытайтесь зайти просто на `http://127.0.0.1:8001` — это не сработает. Используйте полный URL из шага 2.

## Замечания / улучшения (IDEAS)
- Добавить оператор Postgres вместо ручного StatefulSet
- Перейти на OpenAPI 3 (servers вместо schemes)
- Helm chart / kustomize для параметризации тегов образов
- Переключение CronJob расписания через переменную окружения / значения ConfigMap

---
**License:** MIT
