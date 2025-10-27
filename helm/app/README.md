# K8S-HW Helm Chart

Этот Helm-чарт развёртывает полное приложение k8s-hw, включающее backend приложение и PostgreSQL базу данных.

## Архитектура

Чарт представляет собой umbrella chart (зонтичный чарт) с двумя подчартами:

- **postgres** - PostgreSQL StatefulSet с PVC, сервисами, секретами и конфигурацией
- **backend** - Backend приложение с Deployment, CronJob, миграциями, Ingress и PVC

Backend автоматически ссылается на ресурсы PostgreSQL (secrets и configmap) для подключения к базе данных.

## Структура

```
helm/app/
├── Chart.yaml              # Метаданные чарта и объявления зависимостей
├── values.yaml             # Значения верхнего уровня (опционально)
├── templates/
│   └── _helpers.tpl        # Вспомогательные функции для шаблонов
└── charts/
    ├── backend/
    │   ├── Chart.yaml
    │   ├── values.yaml     # Конфигурация backend приложения
    │   └── templates/
    │       ├── config-map.yaml      # ConfigMap приложения
    │       ├── secret.yaml          # Secrets приложения
    │       ├── deployment.yaml      # Deployment с 2 репликами
    │       ├── service.yaml         # ClusterIP service
    │       ├── cronjob.yaml         # CronJob для фоновых задач
    │       ├── migrations-job.yaml  # Job для миграций БД
    │       ├── ingress.yaml         # Ingress для HTTP(S)
    │       ├── pvc.yaml             # PVC для данных приложения
    │       └── tests/
    └── postgres/
        ├── Chart.yaml
        ├── values.yaml     # Конфигурация PostgreSQL
        └── templates/
            ├── config-map.yaml      # ConfigMap с host/port
            ├── secrets.yaml         # Secrets с credentials
            ├── db.yaml              # StatefulSet
            ├── service.yaml         # Headless + обычный + NodePort
            └── tests/
```

## Зависимости

Чарт имеет следующие зависимости, объявленные в `Chart.yaml`:

```yaml
dependencies:
  - name: postgres
    version: 0.1.0
    repository: "file://charts/postgres"
  - name: backend
    version: 0.1.0
    repository: "file://charts/backend"
    condition: backend.enabled
```

## Установка

### Предварительные требования

1. Kubernetes кластер (например, Docker Desktop, Minikube, или облачный провайдер)
2. Helm 3.x установлен
3. kubectl настроен для работы с кластером
4. Docker образы приложения опубликованы (или используются latest)

### Быстрая установка

```bash
# Через Makefile (рекомендуется)
make helm-deploy

# Или напрямую через helm
helm install k8s-hw-app helm/app/ -n k8s-hw --create-namespace
```

### Установка с кастомными параметрами

```bash
# С определённой версией образов
make helm-install VERSION=1.2.3

# Или через helm с дополнительными параметрами
helm install k8s-hw-app helm/app/ \
  -n k8s-hw --create-namespace \
  --set backend.images.backend.tag=1.2.3 \
  --set backend.images.migrations.tag=1.2.3 \
  --set backend.images.cron.tag=1.2.3 \
  --set backend.replicaCount=3 \
  --set postgres.statefulset.replicas=2
```

## Обновление

```bash
# Через Makefile
make helm-upgrade VERSION=1.2.4

# Или напрямую
helm upgrade k8s-hw-app helm/app/ -n k8s-hw \
  --set backend.images.backend.tag=1.2.4
```

## Удаление

```bash
# Через Makefile
make helm-uninstall

# Или напрямую
helm uninstall k8s-hw-app -n k8s-hw
kubectl delete namespace k8s-hw
```

## Конфигурация

### Backend (charts/backend/values.yaml)

#### Образы

```yaml
images:
  backend:
    name: fastrapier1/k8s-test-backend-app
    tag: latest
    imagePullPolicy: IfNotPresent
  cron:
    name: fastrapier1/k8s-test-backend-cron
    tag: latest
    imagePullPolicy: IfNotPresent
  migrations:
    name: fastrapier1/k8s-test-backend-migrations
    tag: latest
    imagePullPolicy: IfNotPresent
```

#### Переменные окружения

Backend поддерживает несколько типов переменных окружения:

1. **configmap** - из собственного ConfigMap приложения
2. **secrets** - из собственных Secrets приложения
3. **postgresConfigmap** - из PostgreSQL ConfigMap (host, port)
4. **postgresSecrets** - из PostgreSQL Secrets (credentials)

```yaml
env:
  configmap:
    APP_CONFIG_MAP_ENV_VAR: APP_CONFIG_MAP_ENV_VAR
  secrets:
    APP_SECRET_USERNAME: username
    APP_SECRET_PASSWORD: password
  postgresConfigmap:
    APP_POSTGRES_HOST: host
    APP_POSTGRES_PORT: port
  postgresSecrets:
    APP_POSTGRES_USER: username
    APP_POSTGRES_PASSWORD: password
    APP_POSTGRES_DB: database

# Фактические данные для ConfigMap и Secrets
configmapData:
  APP_CONFIG_MAP_ENV_VAR: test-value-from-helm-values

secretData:
  username: developer
  password: password
```

#### Реплики и стратегия

```yaml
replicaCount: 2

strategy:
  rollingUpdate:
    maxUnavailable: 1
  type: RollingUpdate
```

#### Ссылки на PostgreSQL

```yaml
postgres:
  configmapName: postgres-configmap
  secretName: postgres-secrets
```

### PostgreSQL (charts/postgres/values.yaml)

#### Credentials

```yaml
secret:
  username: lamarr
  password: qwerty12345
  database: db
```

#### StatefulSet конфигурация

```yaml
statefulset:
  replicas: 1
  image:
    name: postgres
    tag: 17
    pullPolicy: IfNotPresent
  pvc:
    name: data
    mountPath: /bitnami/postgresql
    accessMode: ReadWriteOnce
    size: 1Gi
  env:
    value:
      PGDATA: /bitnami/postgresql/data
    secret:
      POSTGRES_PASSWORD: password
      POSTGRES_DB: database
      POSTGRES_USER: username
```

#### Сервисы

```yaml
service:
  port:
    name: postgresql
    node: 30432
    inner: 5432
    protocol: TCP
```

Создаются три сервиса:
- **Headless Service** - для StatefulSet DNS
- **ClusterIP Service** - для внутреннего доступа
- **NodePort Service** - для внешнего доступа (порт 30432)

## Проверка развёртывания

```bash
# Просмотр всех ресурсов
kubectl get all -n k8s-hw

# Просмотр подов
kubectl get pods -n k8s-hw

# Логи приложения
kubectl logs -n k8s-hw -l app.kubernetes.io/name=backend

# Логи PostgreSQL
kubectl logs -n k8s-hw -l app.kubernetes.io/name=postgres

# Проверка Job миграций
kubectl get jobs -n k8s-hw
kubectl logs -n k8s-hw job/backend-migrations
```

## Тестирование

```bash
# Lint чарта
make helm-lint

# Просмотр результирующих манифестов
make helm-template

# Запуск тестов чарта
helm test k8s-hw-app -n k8s-hw
```

## Устранение неполадок

### Поды не запускаются

Проверьте события и логи:

```bash
kubectl describe pod -n k8s-hw <pod-name>
kubectl logs -n k8s-hw <pod-name>
```

### Миграции не выполняются

```bash
# Проверить статус Job
kubectl get job backend-migrations -n k8s-hw

# Посмотреть логи
kubectl logs -n k8s-hw job/backend-migrations

# При необходимости удалить и пересоздать
kubectl delete job backend-migrations -n k8s-hw
helm upgrade k8s-hw-app helm/app/ -n k8s-hw
```

### Backend не может подключиться к PostgreSQL

Проверьте, что:
1. PostgreSQL под запущен и готов
2. ConfigMap и Secrets созданы корректно
3. Имена ресурсов совпадают в backend values

```bash
kubectl get configmap postgres-configmap -n k8s-hw -o yaml
kubectl get secret postgres-secrets -n k8s-hw -o yaml
```

## Лучшие практики

1. **Secrets в production**: Используйте внешние системы управления секретами (Vault, Sealed Secrets, External Secrets Operator)
2. **Версионирование**: Всегда указывайте версии образов вместо `latest`
3. **Ресурсы**: Добавьте requests/limits для CPU и памяти в production
4. **Мониторинг**: Интегрируйте с Prometheus/Grafana для мониторинга
5. **Бэкапы БД**: Настройте регулярные бэкапы PostgreSQL

## Отличия от прямого развёртывания через kubectl

| Аспект | kubectl apply | Helm |
|--------|--------------|------|
| Управление | Файлы манифестов | Чарты |
| Параметризация | Ручная правка YAML | Values.yaml + --set |
| Обновление | Повторный apply | helm upgrade |
| Откат | Сложно | helm rollback |
| Версионирование | Git | Helm releases |
| Зависимости | Ручное управление | Автоматическое |

## Дополнительная информация

- Основной README проекта: `../../README.md`
- Backend chart: `charts/backend/README.md` (если есть)
- PostgreSQL chart: `charts/postgres/README.md` (если есть)
