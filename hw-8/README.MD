# ДЗ 8 — Работа с CI/CD

Часть 1: тег образа считает semantic-release, образ собирается и публикуется в GHCR,
деплой в Kubernetes идёт по этому же тегу.

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
│  runs-on: ubuntu-latest     │  kubectl rollout status + kubectl get pods                │
│   (часть 2 → self-hosted)   │                                                           │
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
├── init.sh                     # Точка входа: dry-run версии + деплой в minikube
├── teardown.sh                 # Полная очистка
├── TASK.MD                     # Задание
├── CHECKLIST.MD                # Чеклист для защиты
│
├── scripts/
│   ├── common.sh               # Общие функции (namespace, GHCR, helm, minikube)
│   ├── 01-release-dry-run.sh   # semantic-release --dry-run: какая версия получится
│   └── 02-deploy.sh [TAG]      # helm upgrade --install по тегу образа
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

`concurrency` с `cancel-in-progress` отменяет предыдущий прогон на той же ветке,
чтобы два релиза не гонялись за тегом одновременно.

### Джобы

| Джоба | `runs-on` | permissions | Что делает |
|---|---|---|---|
| `release` | ubuntu-latest | `contents: write`, `issues: write`, `pull-requests: write` | semantic-release: считает версию, на main создаёт тег и Release |
| `build` | ubuntu-latest | `contents: read`, `packages: write` | buildx: собирает образ, на main пушит `:<version>` и `:latest` в GHCR |
| `deploy` | ubuntu-latest | `contents: read` | `helm upgrade --install` по тегу + `kubectl rollout status` |

Логин в GHCR — через встроенный `secrets.GITHUB_TOKEN` и `permissions: packages: write`,
отдельный PAT не нужен. Образ — `ghcr.io/${{ github.repository_owner }}/hw8`.

На PR джоба `build` собирает образ (проверка, что Dockerfile не сломан), но
**не пушит** его: `push: false`, тег `…:<version>-pr<N>` только для локальной метки.

### Про джобу deploy и часть 2

`deploy` берёт kubeconfig из секрета `KUBECONFIG` (base64). Если секрет не задан,
шаг **не падает**, а печатает `::warning::` и пропускает деплой:

```bash
if [ -z "$KUBECONFIG_B64" ]; then
  echo "::warning::Секрет KUBECONFIG не задан — деплой пропущен."
  echo "ready=false" >> "$GITHUB_OUTPUT"
  exit 0
fi
```

Причина: GitHub-hosted раннер живёт в облаке GitHub и **физически не может достучаться
до minikube на ноутбуке** — у кластера нет публичного адреса, а класть kubeconfig
локального кластера в секреты бессмысленно. Ровно эту проблему решает часть 2 ДЗ:
self-hosted раннер, поднятый *внутри* кластера через helm-чарт, получает доступ к
API-серверу изнутри. Тогда в этой джобе достаточно поменять `runs-on: ubuntu-latest`
на self-hosted-label — остальные шаги (`helm upgrade --install` с тем же `--set image.tag`)
не меняются.

Пока часть 2 не сделана, деплой по тегу выполняется локально тем же чартом:
`./scripts/02-deploy.sh 1.0.0`.

## Быстрый старт

Локальный деплой уже опубликованного тега в minikube:

```bash
minikube start
minikube tunnel                 # отдельный терминал, нужен для Ingress
cd hw-8
./init.sh                       # последний git-тег (или latest)
./init.sh 1.0.0                 # конкретный тег
./scripts/02-deploy.sh 1.0.0    # только деплой, без dry-run версии
```

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

Теги и GitHub Releases `teardown.sh` не удаляет — ими управляет semantic-release.
Если нужно откатить релиз вручную:

```bash
gh release delete v1.0.0 --yes
git push --delete origin v1.0.0
git tag -d v1.0.0
```
