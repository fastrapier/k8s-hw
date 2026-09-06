# ДЗ 9 — Werf

Приложение из ДЗ 1-2 (Go HTTP API + PostgreSQL) переехало из «чарт + Makefile + helm-secrets»
в самодостаточный werf-проект: `werf.yaml` + `.helm/` с сабчартами и глобальными values.
Секреты и docker-токен приезжают из Vault одним скриптом интеграции.

## Архитектура

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  scripts/02-vault-integration.sh                                                     │
│                                                                                      │
│   1. AppRole login          role_id + secret_id ──► Vault ──► client token            │
│                                                                                      │
│   2. docker-токен           vault kv get secret/docker ──┐                            │
│                                                          ▼                            │
│                              WERF_PASSWORD=<token> werf cr login ghcr.io              │
│                                                          │                            │
│   3. секреты приложения     vals eval -f secret-values.tpl.yaml                       │
│                              ref+vault://secret/postgres#/password  ──► значения      │
│                              ref+vault://secret/backend#/password        (tmp-файл)   │
│                                                          │                            │
│   4. деплой                 werf converge --values <tmp> --set-docker-config-json-value│
└──────────────────────────────────┬───────────────────────────────────────────────────┘
                                   │
        ┌──────────────────────────┴─────────────┐
        │ werf: build → push → deploy            │
        ▼                                        ▼
┌────────────────────────┐        ┌──────────────────────────────────────────────────┐
│ GHCR                   │        │  Kubernetes (minikube, namespace k8s-hw9)        │
│ ghcr.io/fastrapier/hw9 │        │                                                  │
│   app                  │──pull─►│  Secret ghcr-pull-secret ◄── dockerconfigjson    │
│   cron                 │        │  Secret postgres-secret  ◄── Vault (vals)        │
│   migrations           │        │  Secret backend-secret   ◄── Vault (vals)        │
└────────────────────────┘        │                                                  │
                                  │  StatefulSet postgres ──► PVC data-postgres-0    │
                                  │        ▲            ConfigMap postgres-config    │
                                  │        │ (host/port/creds)                       │
                                  │  Job backend-migrations (helm post-install hook) │
                                  │        │ golang-migrate up                       │
                                  │        ▼                                         │
                                  │  Deployment backend (2 реплики) ──► PVC          │
                                  │        │  Service backend :80 → :8080            │
                                  │        ▼                                         │
                                  │  Ingress app-hw9.local                           │
                                  │  CronJob backend-cron (раз в минуту → cron_runs) │
                                  └──────────────────────────────────────────────────┘

  Vault (dev-mode, helm hashicorp/vault, ingress vault-hw9.local)
    secret/docker    registry, username, token   ← из macOS Keychain, ставит 01-setup-vault.sh
    secret/postgres  username, password, database
    secret/backend   username, password
    policy app-policy  +  AppRole app-role
```

## Структура werf-проекта

```
hw-9/
├── werf.yaml                   # project: hw9, три образа из Dockerfile-ов
├── init.sh                     # 01 → 02
├── teardown.sh                 # werf dismiss + Vault + PVC + /etc/hosts
├── TASK.MD  README.MD  CHECKLIST.MD
├── secret-values.tpl.yaml      # шаблон для vals: только ref+vault://, без значений
├── .gitignore                  # secret-values.rendered.yaml не попадает в git
│
├── main.go                     # исходники приложения — часть werf-проекта
├── cmd/cronjob/main.go
├── internal/{api,config,db,handler}/
├── docs/                       # swagger.json + embed
├── migrations/                 # 0001_requests, 0002_cron_runs
├── go.mod                      # module hw-9, go 1.26
│
├── docker/
│   ├── app.Dockerfile          # image: app
│   ├── cron.Dockerfile         # image: cron
│   └── migrations.Dockerfile   # image: migrations (golang-migrate)
│
├── scripts/
│   ├── common.sh               # namespace, хосты, GHCR, AppRole login, чтение Vault
│   ├── 01-setup-vault.sh       # Vault dev + секреты + политика + AppRole
│   ├── 02-vault-integration.sh # ключевой скрипт задания (см. ниже)
│   └── migrations-entrypoint.sh# entrypoint образа миграций
│
└── .helm/                      # чарт релиза (werf ищет его именно здесь)
    ├── Chart.yaml              # dependencies → сабчарты, condition на enabled
    ├── Chart.lock              # helm dependency update
    ├── values.yaml             # global: всё общее + пустые слоты под секреты
    ├── templates/
    │   ├── pull-secret.yaml    # ghcr-pull-secret из global.werf.dockerconfigjson
    │   └── NOTES.txt
    └── charts/                 # helm submodules
        ├── postgres/           # StatefulSet + 3 Service + ConfigMap + Secret
        └── backend/            # Deployment + Service + Ingress + PVC
                                # + CronJob + Job миграций + ConfigMap + Secret
```

## Что изменилось относительно ДЗ 1-2

| Было (hw1-2) | Стало (hw-9) |
|---|---|
| `helm/app/` — чарт лежит рядом с кодом, но живёт сам по себе | `.helm/` — чарт релиза внутри werf-проекта, werf находит его сам |
| `Makefile` на ~300 строк: docker build/push, kubectl apply, миграции, ingress, TLS | `werf.yaml` (11 строк) + `werf converge`: сборка, push и деплой одной командой |
| Теги образов `latest`, `imagePullPolicy` руками | content-based теги werf, образы подставляются в чарт через service values |
| `scripts/deploy-with-secrets.sh` + `.env` + helm-secrets | `scripts/02-vault-integration.sh`: AppRole → vals → `werf converge --values` |
| `ref+vault://` прямо в `values.yaml` чарта | `values.yaml` без секретов вообще, ссылки живут в `secret-values.tpl.yaml` |
| Секреты подставлялись в env как plaintext-значения в манифестах | чарт создаёт объекты `Secret`, поды читают их через `secretKeyRef` |
| Дубли: имя сервиса БД, порт и креды в трёх шаблонах | всё общее в `global`, координаты БД — из ConfigMap/Secret сабчарта postgres |
| Образы из Docker Hub (`fastrapier1/...`), pull secret не нужен | приватные образы в GHCR, `ghcr-pull-secret` из docker-токена в Vault |
| `k8s/*.yaml` — те же ресурсы вторым способом | сырых манифестов нет, единственный источник правды — чарт |

## Три образа werf

`werf.yaml` описывает проект и образы, werf сам считает теги по содержимому:

```yaml
project: hw9
configVersion: 1
---
image: app
dockerfile: docker/app.Dockerfile
```

Готовые ссылки werf кладёт в service values, и пути **разные** на разных уровнях чарта:

| Где | Как обратиться | Значение |
|---|---|---|
| родительский чарт `.helm/templates/` | `.Values.werf.image.app` | `REPO:TAG` |
| сабчарт `.helm/charts/backend/` | `.Values.global.werf.images.app.ref` | `REPO:TAG@DIGEST` |

`.Values.werf` в сабчарты не прокидывается — только `global.werf`. Проверено через
`werf render --dev --stub-tags` с дампом values; в сабчарте backend это обёрнуто в хелпер:

```gotemplate
{{- define "backend.image" -}}
{{- $ctx := index . 0 -}}{{- $name := index . 1 -}}
{{- (index $ctx.Values.global.werf.images $name).ref -}}
{{- end }}
```

```gotemplate
image: {{ include "backend.image" (list . "app") | quote }}
```

## Helm submodules

Сабчарты — обычные директории в `.helm/charts/`, плюс запись в `dependencies` родительского
`Chart.yaml`:

```yaml
dependencies:
  - name: postgres
    version: 1.0.0
    repository: "file://charts/postgres"
    condition: postgres.enabled
```

Почему именно так:

* **`.helm/charts/<name>/`** — helm грузит вложенные чарты из этой директории сам, ничего
  качать не нужно. Это и есть submodules в терминах werf: чарты версионируются вместе с
  проектом, а не тянутся из репозитория чартов.
* **`dependencies` + `condition`** дают выключатель: `--set postgres.enabled=false` убирает
  сабчарт целиком (проверено — в рендере остаются только ресурсы backend).
* **`repository: file://...` + `Chart.lock`** (сгенерирован `helm dependency update .helm`) —
  без lock-файла werf печатает `Cannot automatically download chart dependencies...` прямо
  в stdout, ломая `werf render > manifests.yaml`. Сами `.tgz` в `charts/` не нужны и удалены.

## Глобальные values

`.helm/values.yaml` держит в `global` всё, что нужно больше чем одному сабчарту:

```yaml
global:
  imagePullSecret: ghcr-pull-secret
  ingress:      { className: nginx, host: app-hw9.local }
  backend:      { serviceName: backend, configMapName: ..., secretName: ..., port: 8080, servicePort: 80 }
  postgres:     { serviceName: postgres, headlessServiceName: postgres-headless,
                  configMapName: postgres-config, secretName: postgres-secret, port: 5432 }
  secrets:
    postgres:   { username: "", password: "", database: "" }
    backend:    { username: "", password: "" }
```

Следствия:

* сабчарты не знают друг о друге: backend берёт имя ConfigMap и Secret базы из `global`,
  а не из `.Values.postgres.*` соседнего сабчарта;
* порт БД задан один раз и используется в Service, StatefulSet и ConfigMap;
* `global.secrets.*` в репозитории пустые, а шаблоны обёрнуты в `required` — рендер без
  секретов из Vault падает с внятным сообщением, а не деплоит пустой пароль:

```
Error: ... global.secrets.postgres.username не задан: запустите scripts/02-vault-integration.sh
```

## Скрипт интеграции с Vault

> Презентации к ДЗ у меня нет, поэтому «скрипт интеграции аналогично презентации»
> трактуется так: **один** скрипт логинится в Vault по AppRole, забирает оттуда
> docker-токен и логинится в registry, забирает секреты приложения и передаёт их
> в `werf converge` через `--values`, после чего деплоит проект. Всё, что нужно
> знать werf-у, приезжает из Vault — в репозитории нет ни токена, ни пароля.

`scripts/02-vault-integration.sh`, четыре шага:

**1. AppRole login.** `role_id` + `secret_id` → client token. Дальше все чтения Vault идут
под этим токеном, а не под root — так видно, что политики `app-policy` действительно хватает.
Параллельно поднимается `kubectl port-forward` на 8200: `vals` работает на хосте и должен
видеть Vault по `localhost`.

**2. Docker-токен → `werf cr login`.**

```bash
DOCKER_TOKEN="$(vault_read_field secret/docker token)"
WERF_PASSWORD="$DOCKER_TOKEN" werf cr login "$DOCKER_REGISTRY" -u "$DOCKER_USER"
```

Пароль передаётся переменной окружения, а не аргументом `-p`: аргументы видны в `ps`.
В логи уходит только маска — `ghp_...(40 символов)`.

Логин делается в **отдельный** docker config (`WERF_DOCKER_CONFIG=$(mktemp -d)`). Причина
неочевидная: в пользовательском `~/.docker/config.json` обычно стоит `credsStore: desktop`,
и тогда `werf cr login` кладёт креды в Keychain, а в файле остаётся `"auths": {"ghcr.io": {}}`.
Из такого конфига `imagePullSecret` получится пустым, и поды не смогут скачать образы.
Скрипт после логина проверяет, что секция `auth` в файле появилась, и падает с объяснением,
если нет.

**3. Секреты приложения через `vals`.** В репозитории лежит только шаблон
`secret-values.tpl.yaml` со ссылками:

```yaml
global:
  secrets:
    postgres:
      password: ref+vault://secret/postgres#/password
```

`vals eval -f secret-values.tpl.yaml > secret-values.rendered.yaml` подставляет значения.
Файл создаётся с `chmod 600`, лежит в `.gitignore` и удаляется по `trap` вместе с временным
docker config. Скрипт проверяет, что в результате не осталось ни одной строки `ref+vault://`.

**4. Деплой.**

```bash
werf converge --dev \
  --repo ghcr.io/fastrapier/hw9 \
  --release hw9 --namespace k8s-hw9 \
  --values secret-values.rendered.yaml \
  --set-docker-config-json-value
```

`--set-docker-config-json-value` кладёт base64 docker config в
`.Values.global.werf.dockerconfigjson`, и `.helm/templates/pull-secret.yaml` собирает из него
`ghcr-pull-secret` сам — отдельного `kubectl create secret docker-registry` не нужно.
`--release` и `--namespace` заданы явно, поэтому `--env` werf-у не требуется.

## Быстрый старт

```bash
# токен GHCR (packages:read + write) должен лежать в Keychain:
security add-generic-password -a fastrapier -s ghcr.io -w YOUR_GITHUB_TOKEN -U

minikube start
minikube tunnel          # отдельный терминал
cd hw-9 && ./init.sh     # Vault → интеграция → сборка → деплой
```

## Доступ

| Сервис | URL |
|---|---|
| Приложение | http://app-hw9.local/ |
| Swagger UI | http://app-hw9.local/swagger |
| Vault UI | http://vault-hw9.local (токен `root`) |

Записи в `/etc/hosts` добавляют скрипты, нужен `minikube tunnel`.

Эндпоинты: `/` , `/healthz`, `/readyz`, `/version`, `/test-env` (значение из ConfigMap),
`/secret` (значения из Secret, т.е. из Vault), `/pvc-test`, `/db/requests` (запись в БД).

## Команды werf

```bash
cd hw-9

# что получится — без сборки и без кластера (нужны фиктивные секреты)
werf render --dev --stub-tags \
  --set global.secrets.postgres.username=u --set global.secrets.postgres.password=p \
  --set global.secrets.postgres.database=d \
  --set global.secrets.backend.username=bu --set global.secrets.backend.password=bp

# сборка + деплой (обычно через ./scripts/02-vault-integration.sh)
werf converge --dev --repo ghcr.io/fastrapier/hw9 --release hw9 --namespace k8s-hw9 \
  --values secret-values.rendered.yaml --set-docker-config-json-value

# только сборка и push
werf build --dev --repo ghcr.io/fastrapier/hw9

# логин в registry
WERF_PASSWORD=<token> werf cr login ghcr.io -u fastrapier

# удалить релиз
werf dismiss --release hw9 --namespace k8s-hw9
```

## Проверка

```bash
kubectl get pods,svc,ingress,cronjob -n k8s-hw9
kubectl logs job/backend-migrations -n k8s-hw9      # golang-migrate up
kubectl get secret postgres-secret -n k8s-hw9 -o jsonpath='{.data.password}' | base64 -d
curl http://app-hw9.local/secret                     # то же значение, что в Vault
curl -X POST http://app-hw9.local/db/requests
```

## Что проверено, а что нет

Проверено статически, без кластера (Docker и minikube не поднимались):

* `go build ./... && go vet ./... && go test ./...` — зелёные, module `hw-9`;
* `werf render --dev --stub-tags` — зелёный, отдаёт Deployment, StatefulSet, Job, CronJob,
  4 Service, Ingress, 2 ConfigMap, 3 Secret, PVC;
* рендер **без** секретов падает на `required` — как и задумано;
* `--set postgres.enabled=false` действительно выключает сабчарт;
* подстановка образов по именам проверена через `helm template` с подменой
  `global.werf.images.*.ref`;
* `bash -n` для всех скриптов; `vals eval` на шаблоне разбирает `ref+vault://` (падает
  только на отсутствии Vault).

Живьём **не проверялось**: сборка образов, `werf cr login`, push в GHCR, `werf converge`
в кластер, работа Job миграций и CronJob, доступность приложения через Ingress.

## Очистка

```bash
./teardown.sh
kubectl delete namespace k8s-hw9
```

## Чеклист для защиты

**[CHECKLIST.MD](CHECKLIST.MD)**
