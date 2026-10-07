# ДЗ 8 — Работа с CI/CD

Часть 1: тег образа считает semantic-release, образ собирается и публикуется в GHCR,
деплой в Kubernetes идёт по этому же тегу.

Часть 2: свой раннер в minikube, поднятый helm-чартом Actions Runner Controller;
джоба `deploy` уезжает на него и деплоит изнутри кластера —
**[Часть 2 — свой раннер](#часть-2--свой-раннер)**.

## Архитектура пайплайна

```
                        ┌──────────────────────────────────────────────┐
   git push / PR ──────►│  GitHub Actions: .github/workflows/          │
                        │                  hw8-release.yml             │
                        └───────────────────────┬──────────────────────┘
                                                │
   ┌────────────────────────────────────────────┴────────────────────────────────────────┐
   │                                                                                     │
   ▼                                                                                     │
┌─────────────────────────────┐                                                          │
│ job: release                │  npx semantic-release                                    │
│  «Сборка тега»              │   ├─ читает Conventional Commits из истории git          │
│                             │   ├─ считает следующую версию (semver)                   │
│  PR      → --dry-run        │   ├─ exec: printf version > hw-8/.version                │
│  main    → реальный релиз   │   └─ github: git-тег vX.Y.Z + GitHub Release с notes     │
│                             │                                                          │
│  outputs: version, released │                                                          │
└──────────────┬──────────────┘                                                          │
               │ version=1.0.0, released=true|false                                      │
               ▼                                                                         │
┌─────────────────────────────┐                                                          │
│ job: build                  │  docker buildx build                                     │
│  «Сборка образа по тегу»    │   context: hw-8                                          │
│                             │   file:    hw-8/docker/app.Dockerfile                    │
│  PR   → push: false         │   build-args: VERSION=<version>, COMMIT=<sha>             │
│  main → push: true          │   tags: ghcr.io/fastrapier/hw8:<version>                 │
│                             │         ghcr.io/fastrapier/hw8:latest                    │
└──────────────┬──────────────┘                                                          │
               │                                                                         │
               ▼                                                                         │
┌─────────────────────────────┐                                                          │
│ job: deploy                 │  helm upgrade --install hw8-app hw-8/helm/app             │
│  «Деплой по тегу»           │    -n k8s-hw8 --create-namespace                          │
│  if: released == 'true'     │    --set image.tag=<version> --wait                       │
│      или -f tag=X.Y.Z       │  kubectl rollout status + kubectl get pods                │
│                             │                                                          │
│  runs-on:                   │  часть 2: если repo variable HW8_RUNNER задана —          │
│   vars.HW8_RUNNER           │  джоба идёт на self-hosted раннере внутри minikube,       │
│   или ubuntu-latest         │  см. «Часть 2 — свой раннер»                              │
└──────────────┬──────────────┘                                                          │
               │                                                                         │
               ▼                                                                         │
   ┌──────────────────────────────────────────┐        локально: ./scripts/02-deploy.sh   │
   │  Kubernetes (namespace k8s-hw8)          │◄───────────────────────────────────────────┘
   │                                          │        (тот же чарт, тот же --set image.tag)
   │   Deployment hw8-app (2 реплики)         │
   │     image: ghcr.io/fastrapier/hw8:1.0.0  │
   │     env APP_VERSION=1.0.0                │
   │     readiness/liveness: GET /healthz     │
   │   Service hw8-app :80 → :8080            │
   │   Ingress hw8.local (опционально)        │
   └──────────────────────────────────────────┘
```

## Структура проекта

```
.github/workflows/
└── hw8-release.yml             # Пайплайн: release → build → deploy
                                # (workflow ОБЯЗАН лежать в корне репозитория)

hw-8/
├── init.sh                     # Точка входа: dry-run версии + деплой + раннер
├── teardown.sh                 # Полная очистка (включая раннер и ARC)
├── TASK.MD                     # Задание
├── CHECKLIST.MD                # Чеклист для защиты
│
├── scripts/
│   ├── common.sh               # Общие функции (namespace, GHCR, helm, minikube, ARC)
│   ├── 01-release-dry-run.sh   # semantic-release --dry-run: какая версия получится
│   ├── 02-deploy.sh [TAG]      # helm upgrade --install по тегу образа
│   └── 03-deploy-runner.sh     # Часть 2: ARC + scale set + RBAC + HW8_RUNNER
│
├── arc/                        # Часть 2: свой раннер (Actions Runner Controller)
│   ├── runner-values.yaml      # Values для чарта gha-runner-scale-set
│   └── deployer-rbac.yaml      # SA раннера + права на helm upgrade в k8s-hw8
│
├── cmd/app/main.go             # Go HTTP-сервис: GET /healthz, GET /version, GET /
├── go.mod                      # module hw-8, go 1.26 (без внешних зависимостей)
├── docker/
│   └── app.Dockerfile          # Многостадийный, ARG VERSION / ARG COMMIT → -ldflags
│
├── helm/app/                   # Чарт приложения (используется и в CI, и локально)
│   ├── Chart.yaml
│   ├── values.yaml             # image.repository, image.tag (обязателен), ingress
│   └── templates/
│       ├── _helpers.tpl        # labels + required для image.tag
│       ├── deployment.yaml     # env APP_VERSION, probes на /healthz
│       ├── service.yaml
│       └── ingress.yaml
│
├── .releaserc.json             # Конфиг semantic-release
├── package.json                # devDependencies semantic-release
└── package-lock.json           # для npm ci в CI
```

## Приложение

Минимальный Go-сервис без внешних зависимостей — тема ДЗ про CI/CD, а не про код,
поэтому Vault / RabbitMQ / Redis из прошлых ДЗ здесь сознательно не используются.

| Эндпоинт | Ответ |
|---|---|
| `GET /healthz` | `{"status":"ok"}` — используется в readiness/liveness |
| `GET /version` | `{"version":"1.0.0","commit":"<sha>","env_version":"1.0.0"}` |
| `GET /` | `hw-8 CI/CD demo — version 1.0.0 (<sha>)` |

`version` и `commit` — не из env, а зашиты в бинарник линкером:

```dockerfile
ARG VERSION=dev
ARG COMMIT=none
RUN go build -ldflags "-X main.version=${VERSION} -X main.commit=${COMMIT}" ...
```

Так по `/version` видно, из какого именно тега и коммита собран образ, даже если
Helm-значения потом поменяли. `env_version` — это `APP_VERSION` из Deployment: если
эти два поля разошлись, значит задеплоен не тот тег, что собран.

Проверить локально:

```bash
cd hw-8
go build ./... && go vet ./...
go run -ldflags "-X main.version=0.0.1-local" ./cmd/app
curl localhost:8080/version
```

## semantic-release

Конфиг — `hw-8/.releaserc.json`. Версия считается **только по сообщениям коммитов**,
руками теги не создаются.

### Правила: коммит → bump версии

| Коммит | Bump | Пример |
|---|---|---|
| `feat: ...` | **minor** (1.0.0 → 1.1.0) | `feat(hw-8): добавить эндпоинт /metrics` |
| `fix: ...` | **patch** (1.0.0 → 1.0.1) | `fix(hw-8): исправить readiness probe` |
| `perf:`, `refactor:`, `ci:`, `build:` | **patch** | `ci(hw-8): пинить actions по мажору` |
| `docs:`, `test:`, `style:`, `chore:` | нет релиза | `docs(hw-8): дополнить README` |
| `feat!: ...` или тело с `BREAKING CHANGE:` | **major** (1.0.0 → 2.0.0) | `feat(hw-8)!: сменить порт на 9090` |

Первый релиз — всегда `1.0.0` (тегов в репозитории ещё нет), независимо от типа коммита.

### Что важно знать

- **Merge-коммиты игнорируются.** `commit-analyzer` не разбирает `Merge pull request #N ...`
  как Conventional Commit — такой коммит не даёт релиза. Поэтому PR нужно мержить
  **squash-мержем с conventional-заголовком** либо обычным merge-коммитом, но тогда
  версию поднимут conventional-коммиты внутри ветки.
- **Формат тега — `v${version}`** (`v1.0.0`), а тег docker-образа — без `v` (`:1.0.0`).
- **Теги общие на весь репозиторий.** Репозиторий один, ДЗ в нём несколько, поэтому
  `v1.0.0` — это версия репозитория, а не только `hw-8/`. Это осознанное упрощение:
  разводить независимые версии по подпапкам (monorepo-релизы) — отдельная задача,
  выходящая за рамки ДЗ. Из-за этого `paths:`-фильтр в workflow ограничивает только
  запуск пайплайна, но не подсчёт версии.
- **semantic-release читает историю из корня git, а конфиг — из cwd.** Поэтому в
  workflow используется `working-directory: hw-8` и `fetch-depth: 0` у checkout:
  без полной истории и тегов версия посчитается неверно.
- **Плагинов `@semantic-release/npm` и `@semantic-release/git` нет.** Публиковать пакет
  в npm не нужно, а коммитить CHANGELOG обратно в репозиторий из CI — лишний коммит
  и риск зацикливания пайплайна. Release notes живут в GitHub Release.

### Передача версии между джобами

`@semantic-release/exec` на шаге `verifyReleaseCmd` (он выполняется и в dry-run,
в отличие от `prepare`/`publish`) пишет версию в файл:

```json
["@semantic-release/exec", { "verifyReleaseCmd": "printf '%s' '${nextRelease.version}' > .version" }]
```

Следующий шаг workflow читает `hw-8/.version` и выставляет outputs `version` и `released`.
Если релиз не нужен, файла нет → `version` пустой, `released=false`, джобы `build`
(push) и `deploy` не публикуют и не деплоят.

### Локальная проверка версии

```bash
cd hw-8
export GITHUB_TOKEN=$(gh auth token)
./scripts/01-release-dry-run.sh
```

Скрипт подставляет текущую ветку через `--branches`, потому что semantic-release
требует, чтобы HEAD был на релизной ветке **и** чтобы эта ветка существовала в `origin`.
Локально мы почти всегда не на `main`, поэтому без подстановки dry-run падает с
`ERELEASEBRANCHES`.

### Грабли: dry-run на pull_request

Имя ветки semantic-release берёт не из git, а из переменных CI (пакет `env-ci`).
На событии `pull_request` `GITHUB_REF` равен `refs/pull/<N>/merge`, такая «ветка» не
совпадает ни с одной релизной, и semantic-release выходит с сообщением
`This test run was triggered on the branch refs/pull/7/merge, while semantic-release
is configured to only publish from ...` — **не посчитав версию**. Внешне прогон
зелёный, но `version` пустой, и `build` собирает образ с меткой `0.0.0-pr<N>`.

Поэтому в dry-run-ветке workflow признаки CI гасятся:

```bash
CI= GITHUB_ACTIONS= GITHUB_REF= npx semantic-release --dry-run --no-ci --branches "$BRANCH"
```

Тогда ветка определяется по git HEAD, а `checkout` заранее поставлен на реальную
ветку PR (`ref: ${{ github.head_ref }}`), а не на detached merge-коммит.

## Helm-чарт

Один и тот же чарт `hw-8/helm/app` используется и в CI, и локально — тег передаётся
одинаково, через `--set image.tag=<version>`:

```bash
helm upgrade --install hw8-app hw-8/helm/app \
  -n k8s-hw8 --create-namespace \
  --set image.tag=1.0.0 --wait
```

`image.tag` не имеет значения по умолчанию и обёрнут в `required`: рендер падает,
если тег не передали. Это защита от «случайно задеплоили `:latest`» — весь смысл ДЗ
в том, что деплоится конкретный собранный тег.

Проверка чарта без кластера:

```bash
cd hw-8
helm lint helm/app --set image.tag=1.0.0
helm template hw8-app helm/app --set image.tag=1.0.0
helm template hw8-app helm/app          # должно упасть: image.tag обязателен
```

### Почему без werf

В ДЗ 3 и 4 сборка и деплой шли через `werf converge`. Здесь werf сознательно не
используется:

- werf сам вычисляет теги образов по контенту (content-based tagging), а задание
  требует деплоить **тег из semantic-release** — две системы версионирования
  конфликтовали бы;
- `docker/build-push-action` + `helm upgrade --install` — стандартный, читаемый набор
  для GitHub Actions, где каждый шаг пайплайна виден отдельно;
- werf в CI требует своего кеша и стейта, что усложняет разбор задания.

## GitHub Actions

Файл — `.github/workflows/hw8-release.yml`. GitHub читает workflow **только** из
`.github/workflows/` в корне репозитория, поэтому он лежит не в `hw-8/`, а в корне;
всё остальное по ДЗ — внутри `hw-8/`. Фильтр `paths: [hw-8/**, .github/workflows/hw8-release.yml]`
не даёт пайплайну запускаться на изменения в других ДЗ.

### Триггеры

| Событие | Что делает |
|---|---|
| `pull_request` → `main` | `release` в `--dry-run` (показывает будущую версию), `build` без push |
| `push` → `main` | реальный релиз: тег + GitHub Release, push образа в GHCR, деплой |
| `workflow_dispatch` | ручной запуск, ведёт себя как PR (dry-run) |
| `workflow_dispatch -f tag=1.0.0` | только `deploy`: разворачивает уже опубликованный тег, `release` и `build` пропускаются |

`concurrency` с `cancel-in-progress` отменяет предыдущий прогон на той же ветке,
чтобы два релиза не гонялись за тегом одновременно.

### Джобы

| Джоба | `runs-on` | permissions | Что делает |
|---|---|---|---|
| `release` | ubuntu-latest | `contents: write`, `issues: write`, `pull-requests: write` | semantic-release: считает версию, на main создаёт тег и Release |
| `build` | ubuntu-latest | `contents: read`, `packages: write` | buildx: собирает образ, на main пушит `:<version>` и `:latest` в GHCR |
| `deploy` | `vars.HW8_RUNNER` или ubuntu-latest | `contents: read` | `helm upgrade --install` по тегу + `kubectl rollout status` |

Логин в GHCR — через встроенный `secrets.GITHUB_TOKEN` и `permissions: packages: write`,
отдельный PAT не нужен. Образ — `ghcr.io/${{ github.repository_owner }}/hw8`.

На PR джоба `build` собирает образ (проверка, что Dockerfile не сломан), но
**не пушит** его: `push: false`, тег `…:<version>-pr<N>` только для локальной метки.

### Откуда джоба deploy берёт доступ к кластеру

Три варианта, в порядке проверки шагом `Kubeconfig`:

1. **Раннер внутри кластера** (часть 2). Если в окружении есть
   `KUBERNETES_SERVICE_HOST`, значит джоба выполняется в поде — `kubectl` и `helm`
   сами берут in-cluster конфиг из токена ServiceAccount, kubeconfig не нужен.
2. **Секрет `KUBECONFIG`** (base64) — для настоящего кластера с публичным адресом.
3. **Ничего из этого** — шаг **не падает**, а печатает `::warning::` и пропускает
   деплой.

Третий вариант — это ровно то, что происходит на GitHub-hosted раннере: он живёт
в облаке GitHub и **физически не может достучаться до minikube на ноутбуке**, у
кластера нет публичного адреса. Класть kubeconfig локального кластера в секреты
бессмысленно — адрес `https://127.0.0.1:<port>` в облаке ведёт в никуда.

## Часть 2 — свой раннер

Раннер поднимается **helm-чартом** внутри того же minikube, где живёт приложение.
Тогда джобе `deploy` не нужен ни публичный адрес кластера, ни kubeconfig в секретах:
она выполняется в поде и обращается к API-серверу изнутри.

### Что такое ARC и почему он

[Actions Runner Controller](https://github.com/actions/actions-runner-controller) —
официальный оператор GitHub для self-hosted раннеров в Kubernetes. Ставится двумя
OCI-чартами:

| Чарт | Namespace | Что делает |
|---|---|---|
| `gha-runner-scale-set-controller` | `arc-systems` | оператор: CRD `AutoscalingRunnerSet`, `EphemeralRunner`, `AutoscalingListener` |
| `gha-runner-scale-set` | `arc-runners` | один *scale set*: описание группы раннеров этого репозитория |

Альтернатива — поставить классический раннер (`config.sh --url ... --token ...`)
руками в контейнере. Не выбрана: задание требует именно helm-чарт, а ARC — это
поддерживаемый GitHub способ, где раннер ещё и **ephemeral** (один под = одна
джоба, после чего под уничтожается) и **автомасштабируемый**.

### Схема

```
   ┌──────────────────────────────────────────────────────────────────┐
   │  GitHub: fastrapier/k8s-hw                                       │
   │   Settings → Actions → Runners → scale set "hw8-minikube"        │
   │   джоба deploy с runs-on: hw8-minikube ждёт свободный раннер     │
   └───────▲──────────────────────────────────────────────┬───────────┘
           │ регистрация раннеров                        │ long poll
           │ (PAT из secret hw8-runner-github-token)     │ «есть работа?»
═══════════╪══════════════════════════════════════════════╪════════════
 minikube  │                                              │
           │      ┌───────────────────────────────────────▼──────────┐
           │      │  namespace arc-systems                           │
           │      │   Deployment arc-gha-rs-controller               │
           │      │     ← helm: gha-runner-scale-set-controller      │
           │      │   Pod …-hw8-minikube-…-listener                  │
           │      │     держит long poll и просит контроллер         │
           │      │     поднять под под конкретную джобу             │
           │      └───────────────────────┬──────────────────────────┘
           │                              │ создаёт EphemeralRunner
           │      ┌───────────────────────▼──────────────────────────┐
           │      │  namespace arc-runners                           │
           └──────┤   AutoscalingRunnerSet hw8-minikube              │
                  │     ← helm: gha-runner-scale-set                 │
                  │     minRunners: 1, maxRunners: 2                 │
                  │   Pod hw8-minikube-…-runner                      │
                  │     ghcr.io/actions/actions-runner               │
                  │     SA: hw8-runner-deployer                      │
                  └───────────────────────┬──────────────────────────┘
                                          │ helm upgrade --install
                                          │ (in-cluster конфиг из
                                          │  токена SA + RoleBinding)
                  ┌───────────────────────▼──────────────────────────┐
                  │  namespace k8s-hw8                               │
                  │   Role/RoleBinding hw8-runner-deployer           │
                  │   Deployment hw8-app                             │
                  │     ghcr.io/fastrapier/hw8:<tag>                 │
                  └──────────────────────────────────────────────────┘
```

Жизненный цикл одной джобы: listener видит задание с label `hw8-minikube` →
контроллер создаёт `EphemeralRunner` → под регистрируется в GitHub и забирает
джобу → джоба делает `helm upgrade` в `k8s-hw8` → под удаляется. Раннер не
переиспользуется между джобами, поэтому мусор от предыдущей сборки не мешает.

### Установка

```bash
cd hw-8
./scripts/03-deploy-runner.sh
```

Скрипт идемпотентен и делает по шагам:

1. создаёт namespace `arc-systems`, `arc-runners`, `k8s-hw8`;
2. `helm upgrade --install arc oci://…/gha-runner-scale-set-controller --version 0.14.2 -n arc-systems --wait`;
3. кладёт PAT в secret `hw8-runner-github-token` (namespace `arc-runners`);
4. применяет `arc/deployer-rbac.yaml` — SA раннера и права на `k8s-hw8`;
5. `helm upgrade --install hw8-minikube oci://…/gha-runner-scale-set --version 0.14.2 -n arc-runners -f arc/runner-values.yaml --wait`;
6. ждёт, пока поднимется под раннера (helm `--wait` ждёт только CR, listener и
   под создаёт уже контроллер), и проверяет регистрацию через
   `gh api repos/fastrapier/k8s-hw/actions/runners`;
7. включает раннер в пайплайне: `gh variable set HW8_RUNNER --body hw8-minikube`.

Версия чартов запинена в `scripts/common.sh` (`ARC_CHART_VERSION`): чарт и образ
контроллера должны совпадать, а «последняя» версия ломает установку при смене CRD.

### Токен

ARC регистрирует раннеры в репозитории от имени PAT — **classic, scope `repo`**
(этого достаточно для раннера уровня репозитория; для раннера уровня организации
нужен ещё `admin:org`). Токен берётся из macOS Keychain — так же, как токен GHCR
в части 1:

```bash
security add-generic-password -a fastrapier -s github-arc -w YOUR_PAT -U
```

Если записи нет, скрипт делает fallback на `gh auth token` и предупреждает: это
OAuth-токен `gh` CLI, он живёт короче PAT и его scope меняет `gh auth refresh`.
В файлы репозитория, в helm values и в логи токен не попадает: он передаётся
только в `kubectl create secret … --dry-run=client -o yaml | kubectl apply -f -`.

В `arc/runner-values.yaml` используется вариант «pre-defined secret» —
`githubConfigSecret` задан **строкой** с именем секрета. Тогда чарт секрет не
создаёт и PAT не проходит через `--set`, то есть не остаётся в истории
helm-релиза.

### RBAC

Чарт `gha-runner-scale-set` по умолчанию создаёт для подов раннера SA
`<scale-set>-gha-rs-no-permission` — как следует из имени, совсем без прав. Нам
нужен SA, который умеет `helm upgrade` в `k8s-hw8`, поэтому в values задан
`template.spec.serviceAccountName: hw8-runner-deployer`: при заданном значении
чарт свой SA не создаёт и берёт наш из `arc/deployer-rbac.yaml`.

| Ресурс | Где | Зачем |
|---|---|---|
| ServiceAccount `hw8-runner-deployer` | `arc-runners` | под этим SA работают поды раннера |
| Role + RoleBinding `hw8-runner-deployer` | `k8s-hw8` | deployments, services, ingresses, pods, secrets, configmaps… — то, что создаёт чарт приложения; secrets ещё и потому, что в них helm хранит состояние релиза |
| ClusterRole + ClusterRoleBinding `hw8-runner-namespace-bootstrap` | кластер | `namespaces`: `get`, `list`, `create` |

Кластерных прав ровно одно, и оно нужно из-за `--create-namespace`: helm всегда
делает `POST /api/v1/namespaces`, ответ `409 AlreadyExists` он игнорирует, а
`403 Forbidden` — нет. То есть без права `create` деплой падал бы даже в уже
созданный namespace.

RoleBinding в `k8s-hw8` ссылается на SA из другого namespace (`arc-runners`) —
это нормально: `subjects` в RoleBinding указывают namespace явно.

### Как раннер включается в пайплайне

`runs-on` джобы `deploy`:

```yaml
runs-on: ${{ vars.HW8_RUNNER || 'ubuntu-latest' }}
```

Repo variable `HW8_RUNNER=hw8-minikube` ставит `03-deploy-runner.sh`, удаляет
`teardown.sh`. Fallback на `ubuntu-latest` **обязателен**: без него джоба, для
которой нет живого раннера с таким label (minikube выключен), просто висела бы в
очереди до таймаута GitHub, а не пропускалась с предупреждением.

```bash
gh variable list --repo fastrapier/k8s-hw          # включён ли раннер
gh variable set HW8_RUNNER --body hw8-minikube     # включить вручную
gh variable delete HW8_RUNNER                      # вернуть деплой на ubuntu-latest
```

Имя scale set = имя helm-релиза = label в `runs-on`. Поэтому «подключить раннер к
проекту» здесь означает не токен в настройках, а `githubConfigUrl` репозитория в
values плюс эту переменную.

### Запуск пайплайна на подключенном раннере

Чтобы не создавать новый релиз ради демонстрации, у `workflow_dispatch` есть
опциональный input `tag`. Если он задан, `release` и `build` пропускаются, а
`deploy` разворачивает уже опубликованный образ:

```bash
gh workflow run hw8-release.yml -f tag=1.0.0
gh run watch
```

В логах джобы `deploy` первый шаг «Где выполняется джоба» печатает `runner.name`,
`RUNNER_ENVIRONMENT=self-hosted`, hostname пода и адрес API-сервера — видно, что
джоба реально уехала в кластер, а не осталась на GitHub-hosted раннере.

Условие джобы из-за этого сложнее обычного `needs`:

```yaml
if: |
  !cancelled() && (
    inputs.tag != '' || (
      needs.release.result == 'success' &&
      needs.build.result == 'success' &&
      needs.release.outputs.released == 'true'
    )
  )
```

Джоба со `skipped`-предшественниками сама уходит в `skipped`, поэтому нужен
`!cancelled()`. Но он же снимает и защиту «не деплоить после падения `build`» —
её приходится вернуть явной проверкой `needs.*.result`.

### Почему build остался на GitHub-hosted раннере

`containerMode` в values не задан: раннер поднимается без dind. Значит `docker
build` внутри него не работает — и это осознанно:

- dind в minikube требует privileged-контейнера и своего слоя хранения, а джоба
  `build` в облаке GitHub уже работает и кеширует слои через `type=gha`;
- задание части 2 — «запустить пайплайн на подключенном раннере», а не «перенести
  всю сборку»; `deploy` — как раз та джоба, которой self-hosted раннер даёт то,
  чего у GitHub-hosted нет: доступ к кластеру;
- смешанный пайплайн (сборка в облаке, деплой в кластере) — типовая схема, а не
  компромисс.

Если dind всё же понадобится: `--set containerMode.type=dind`.

### Диагностика

```bash
# Контроллер и listener
kubectl get pods -n arc-systems
kubectl logs -n arc-systems -l app.kubernetes.io/part-of=gha-rs-controller --tail=50
kubectl logs -n arc-systems -l app.kubernetes.io/component=runner-scale-set-listener --tail=50

# Scale set и поды раннеров
kubectl get autoscalingrunnersets -n arc-runners
kubectl get ephemeralrunners -n arc-runners
kubectl get pods -n arc-runners -w

# Что видит GitHub
gh api repos/fastrapier/k8s-hw/actions/runners \
  --jq '.runners[] | "\(.name) \(.status) \([.labels[].name]|join(","))"'

# Права SA раннера
kubectl auth can-i --as=system:serviceaccount:arc-runners:hw8-runner-deployer \
  create deployments -n k8s-hw8
kubectl auth can-i --as=system:serviceaccount:arc-runners:hw8-runner-deployer \
  create namespaces

# Чарт без установки
helm show values oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2
helm template hw8-minikube oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2 -n arc-runners -f arc/runner-values.yaml
```

### Грабли

- **`helm pull` из ghcr.io отдаёт `403 denied`.** Виноват не чарт: helm берёт
  креды из `~/.docker/config.json`, и если там `credsStore` указывает на
  неработающий helper (например, Docker Desktop не запущен), запрос уходит с
  битым `Authorization` вместо анонимного. Лечится `docker logout ghcr.io` или
  `helm registry login ghcr.io -u <user>`.
- **`helm uninstall` scale set'а зависает.** Finalizer'ы `AutoscalingRunnerSet`
  снимает контроллер, поэтому удалять надо **сначала scale set, потом
  контроллер**. В `teardown.sh` порядок именно такой.
- **Под раннера не появляется, а `helm --wait` уже вернул успех.** `--wait` ждёт
  только сам CR; listener и под создаёт контроллер асинхронно. Поэтому в скрипте
  есть отдельное ожидание пода.
- **`No gha-rs-controller deployment found`** при установке scale set'а — чарт
  ищет SA контроллера через `lookup` по всем деплойментам. В values он задан
  явно (`controllerServiceAccount`), поэтому и `helm template` работает без
  кластера.
- **CRD после `helm uninstall` остаются** — так задумано в чарте, helm не удаляет
  `crds/`. Команда для полной очистки печатается в конце `teardown.sh`.

## Быстрый старт

Скрипты используют активный профиль minikube. Для экзаменационного стенда можно
явно задать `export MINIKUBE_PROFILE=k8s-exam` перед запуском.

Локальный деплой уже опубликованного тега в minikube плюс свой раннер:

```bash
minikube start
minikube tunnel                    # отдельный терминал, нужен для Ingress
cd hw-8
./init.sh                          # последний git-тег (или latest) + раннер
./init.sh 1.0.0                    # конкретный тег
SKIP_RUNNER=1 ./init.sh 1.0.0      # только часть 1, без раннера
./scripts/02-deploy.sh 1.0.0       # только деплой приложения
./scripts/03-deploy-runner.sh      # только раннер (часть 2)
```

`init.sh` выполняет `01` → `02` → `03`. Раннер стоит последним, потому что деплой
приложения от него не зависит: `03` нужен, только чтобы деплой умел приезжать из
пайплайна. `SKIP_RUNNER=1` пропускает этот шаг — например, когда нет PAT.

Полный цикл CI/CD:

```bash
git checkout -b feat/my-change
# ...правки в hw-8/...
git commit -m "feat(hw-8): что-то полезное"
git push -u origin feat/my-change
gh pr create --base main        # в PR: dry-run версии + сборка образа
# после squash-мержа в main: тег vX.Y.Z + Release + образ в GHCR + деплой
```

## Полезные команды

```bash
# Поды и их образы
kubectl get pods -n k8s-hw8 -o wide
kubectl get deployment hw8-app -n k8s-hw8 \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# Версия из работающего приложения
kubectl run curl-hw8 --rm -it --restart=Never -n k8s-hw8 \
  --image=curlimages/curl -- curl -s http://hw8-app/version
curl http://hw8.local/version          # через Ingress, нужен minikube tunnel

# APP_VERSION в логах при старте
kubectl logs deployment/hw8-app -n k8s-hw8 | head

# Теги и релизы
git fetch --tags && git tag -l
gh release list
gh api /users/fastrapier/packages/container/hw8/versions --jq '.[].metadata.container.tags'

# Пайплайн
gh run list --workflow hw8-release.yml
gh run watch
gh run view --log-failed

# Прогон деплоя на своём раннере, без нового релиза
gh variable list
gh workflow run hw8-release.yml -f tag=1.0.0

# Свой раннер
kubectl get pods -n arc-systems
kubectl get pods -n arc-runners
kubectl get autoscalingrunnersets -n arc-runners
gh api repos/fastrapier/k8s-hw/actions/runners \
  --jq '.runners[] | "\(.name) \(.status)"'

# Локальная проверка перед пушем
cd hw-8 && go build ./... && go vet ./...
helm lint helm/app --set image.tag=1.0.0
actionlint ../.github/workflows/hw8-release.yml
```

## Чеклист для защиты

Пошаговый план демонстрации: **[CHECKLIST.MD](CHECKLIST.MD)**

## Очистка

```bash
./teardown.sh
kubectl delete namespace k8s-hw8
```

`teardown.sh` снимает и часть 2: удаляет repo variable `HW8_RUNNER` (сначала её,
чтобы новые джобы не ушли в очередь к умирающему раннеру), затем scale set, затем
контроллер, затем RBAC, секрет и namespace `arc-runners` / `arc-systems`.

Теги и GitHub Releases `teardown.sh` не удаляет — ими управляет semantic-release.
Если нужно откатить релиз вручную:

```bash
gh release delete v1.0.0 --yes
git push --delete origin v1.0.0
git tag -d v1.0.0
```
