# Чеклист для защиты ДЗ 8

## Подготовка

```bash
minikube start
minikube tunnel                # отдельный терминал
git fetch --tags
cd hw-8 && ./init.sh           # деплой последнего тега + раннер, ~5 минут
```

Проверить, что раннер поднялся и подключён:

```bash
kubectl get pods -n arc-systems
kubectl get pods -n arc-runners
gh variable list               # ожидаем HW8_RUNNER=hw8-minikube
```

---

## Порядок демонстрации

Пункты 1–10 — часть 1 (тег, образ, деплой), пункты 11–14 — часть 2 (свой раннер).

### 1. semantic-release — конфигурация

- [ ] Показать конфиг: `hw-8/.releaserc.json`
- [ ] Объяснить состав плагинов:
  - `commit-analyzer` — считает bump по Conventional Commits
  - `release-notes-generator` — собирает release notes
  - `exec` — пишет версию в `hw-8/.version`, чтобы её забрали следующие джобы
  - `github` — создаёт git-тег `vX.Y.Z` и GitHub Release
- [ ] Показать таблицу правил в `README.MD`: `feat` → minor, `fix` → patch,
      `feat!`/`BREAKING CHANGE` → major, `docs`/`chore` → релиза нет
- [ ] Объяснить, почему нет `@semantic-release/npm` и `@semantic-release/git`:
      «в npm не публикуем, CHANGELOG в репозиторий не коммитим»
- [ ] Объяснить про merge-коммиты: «`Merge pull request #N` не является
      Conventional Commit и релиза не даёт, поэтому мержим squash-ом
      с conventional-заголовком»

### 2. semantic-release — вычисление версии вживую

- [ ] Показать dry-run локально:
  ```bash
  cd hw-8
  export GITHUB_TOKEN=$(gh auth token)
  ./scripts/01-release-dry-run.sh
  ```
- [ ] Показать вывод: `The next release version is 1.0.0`
- [ ] Показать, что версия легла в файл:
  ```bash
  cat hw-8/.version
  ```

### 3. Пайплайн в GitHub Actions

- [ ] Показать workflow: `.github/workflows/hw8-release.yml`
- [ ] Объяснить, почему он в корне: «GitHub читает workflow только из
      `.github/workflows/` в корне репозитория»
- [ ] Показать три джобы и связь между ними:
  - `release` → outputs `version`, `released`
  - `build` → `needs: release`, теги образа из `version`
  - `deploy` → `needs: [release, build]`, `if: released == 'true'`
- [ ] Показать триггеры и `paths`-фильтр: пайплайн не запускается на другие ДЗ
- [ ] Показать `concurrency`: два релиза не гонятся за тегом

### 4. Прогон на pull request (dry-run)

- [ ] Открыть прогон PR:
  ```bash
  gh run list --workflow hw8-release.yml
  gh run view <id>
  ```
- [ ] Показать в логах джобы `release`: `Dry-run для ветки ...` и вычисленную версию
- [ ] Показать Summary прогона: `Версия: 1.0.0 (released=false)`
- [ ] Показать джобу `build`: образ собрался, но `push: false` — в GHCR ничего не ушло
- [ ] Показать, что `deploy` пропущена (`released != 'true'`)

### 5. Прогон на main (реальный релиз)

- [ ] Открыть прогон после мержа в `main`:
  ```bash
  gh run list --workflow hw8-release.yml --branch main
  gh run view <id>
  ```
- [ ] Показать в логах: `Реальный релиз: тег и GitHub Release будут созданы`

### 6. Сборка тега — результат

- [ ] Показать созданный git-тег:
  ```bash
  git fetch --tags
  git tag -l
  git show v1.0.0 --stat | head
  ```
- [ ] Показать GitHub Release с release notes:
  ```bash
  gh release list
  gh release view v1.0.0
  ```
- [ ] Обратить внимание: тег создал CI, руками теги не ставились

### 7. Docker-образ на основе тега

- [ ] Показать образ в GHCR:
  ```bash
  gh api /users/fastrapier/packages/container/hw8/versions \
    --jq '.[].metadata.container.tags'
  ```
  Ожидаем теги `1.0.0` и `latest`
- [ ] Открыть страницу пакета: https://github.com/fastrapier?tab=packages
- [ ] Показать Dockerfile и объяснить, как версия попадает в бинарник:
  ```
  ARG VERSION / ARG COMMIT → -ldflags "-X main.version=... -X main.commit=..."
  ```
- [ ] Объяснить, почему git-тег `v1.0.0`, а тег образа `1.0.0` (без `v`)

### 8. Деплой по тегу

- [ ] Показать задеплоенный под и его образ:
  ```bash
  kubectl get pods -n k8s-hw8 -o wide
  kubectl get deployment hw8-app -n k8s-hw8 \
    -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
  ```
  Ожидаем `ghcr.io/fastrapier/hw8:1.0.0` — тот же тег, что собрал CI
- [ ] Показать, что версия внутри приложения совпадает с тегом:
  ```bash
  kubectl run curl-hw8 --rm -it --restart=Never -n k8s-hw8 \
    --image=curlimages/curl -- curl -s http://hw8-app/version
  ```
  Ожидаем `{"version":"1.0.0","commit":"<sha>","env_version":"1.0.0"}`
- [ ] Через Ingress (нужен `minikube tunnel`):
  ```bash
  curl http://hw8.local/version
  ```
- [ ] Показать `APP_VERSION` в логах при старте:
  ```bash
  kubectl logs deployment/hw8-app -n k8s-hw8 | head
  ```
- [ ] Показать readiness/liveness на `/healthz`:
  ```bash
  kubectl describe deployment hw8-app -n k8s-hw8 | grep -A3 -i 'liveness\|readiness'
  ```

### 9. Один чарт для CI и локального деплоя

- [ ] Показать, что тег передаётся одинаково:
  - в CI: шаг `helm upgrade --install` в джобе `deploy`
  - локально: `hw-8/scripts/02-deploy.sh`
- [ ] Показать защиту от деплоя без тега:
  ```bash
  cd hw-8 && helm template hw8-app helm/app
  ```
  Падает с `image.tag обязателен: передайте --set image.tag=...`
- [ ] Объяснить, почему в этом ДЗ не werf: «werf сам версионирует образы по контенту,
      а задание требует деплоить именно тег из semantic-release»

### 10. Почему деплой из GitHub-hosted раннера пропускается

- [ ] Показать шаг `Kubeconfig` в джобе `deploy` и `::warning::` в логах старого прогона
- [ ] Объяснить: «GitHub-hosted раннер в облаке не имеет сетевого доступа к minikube
      на ноутбуке; поэтому шаг честно предупреждает и не падает»
- [ ] Объяснить, что это решает часть 2 — раннер внутри кластера

---

## Часть 2 — свой раннер

### 11. Раннер развёрнут через helm-chart

- [ ] Показать, какими чартами ставится раннер (`hw-8/scripts/common.sh`,
      `ARC_CHART_VERSION`, `ARC_CONTROLLER_CHART`, `ARC_RUNNER_CHART`):
      два OCI-чарта GitHub, версия запинена — `0.14.2`
- [ ] Показать helm-релизы:
  ```bash
  helm list -n arc-systems
  helm list -n arc-runners
  ```
  Ожидаем `arc` (контроллер) и `hw8-minikube` (scale set)
- [ ] Показать поды контроллера и listener'а:
  ```bash
  kubectl get pods -n arc-systems
  ```
- [ ] Показать scale set и под раннера:
  ```bash
  kubectl get autoscalingrunnersets -n arc-runners
  kubectl get pods -n arc-runners
  ```
- [ ] Показать values: `hw-8/arc/runner-values.yaml`
  - `githubConfigUrl` — репозиторий, к которому подключается раннер
  - `githubConfigSecret` строкой — pre-defined secret, PAT не идёт через helm values
  - `minRunners: 1` / `maxRunners: 2`
  - `template.spec.serviceAccountName` — вместо SA без прав, который создал бы чарт
- [ ] Объяснить схему из README: listener держит long poll → контроллер поднимает
      ephemeral-под → под забирает джобу → под удаляется

### 12. Раннер подключён к проекту

- [ ] Показать, что GitHub видит раннер:
  ```bash
  gh api repos/fastrapier/k8s-hw/actions/runners \
    --jq '.runners[] | "\(.name) \(.status) \([.labels[].name]|join(","))"'
  ```
- [ ] То же в UI: Settings → Actions → Runners → scale set `hw8-minikube`
- [ ] Показать, где берётся токен: `arc_github_token` в `scripts/common.sh` —
      classic PAT со scope `repo` из macOS Keychain (`-s github-arc`),
      fallback на `gh auth token` с предупреждением
- [ ] Обратить внимание: токена нет ни в одном файле репозитория, он попадает
      только в secret `hw8-runner-github-token`
- [ ] Показать RBAC: `hw-8/arc/deployer-rbac.yaml`
  ```bash
  kubectl auth can-i --as=system:serviceaccount:arc-runners:hw8-runner-deployer \
    create deployments -n k8s-hw8
  kubectl auth can-i --as=system:serviceaccount:arc-runners:hw8-runner-deployer \
    create deployments -n kube-system      # ожидаем no
  ```
- [ ] Объяснить единственное кластерное право (`namespaces: create`):
      `helm --create-namespace` всегда делает POST, `409` игнорируется, `403` — нет
- [ ] Показать переключатель в пайплайне:
  ```bash
  gh variable list
  ```
  `HW8_RUNNER=hw8-minikube`, а в workflow — `runs-on: ${{ vars.HW8_RUNNER || 'ubuntu-latest' }}`
- [ ] Объяснить fallback: без него джоба висела бы в очереди, когда minikube выключен

### 13. Пайплайн запущен на подключенном раннере

- [ ] Запустить деплой уже опубликованного тега:
  ```bash
  gh workflow run hw8-release.yml -f tag=1.0.0
  gh run watch
  ```
- [ ] Параллельно показать, как появляется под под джобу:
  ```bash
  kubectl get pods -n arc-runners -w
  ```
- [ ] Показать в прогоне, что `release` и `build` пропущены, а `deploy` выполнен
- [ ] Открыть лог шага «Где выполняется джоба» и показать:
  - `runs-on: hw8-minikube`
  - `runner.name` — имя пода раннера
  - `RUNNER_ENVIRONMENT: self-hosted`
  - `внутри кластера: да, API 10.96.0.1`
- [ ] Показать в логе шага `Kubeconfig`: `::notice::Раннер работает внутри
      кластера — используется ServiceAccount hw8-runner-deployer`
      (kubeconfig из секрета не нужен)
- [ ] Показать в логе шага `helm upgrade --install` успешный `helm` и
      `kubectl rollout status`
- [ ] Показать результат в кластере — тег из пайплайна:
  ```bash
  kubectl get deployment hw8-app -n k8s-hw8 \
    -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
  kubectl run curl-hw8 --rm -it --restart=Never -n k8s-hw8 \
    --image=curlimages/curl -- curl -s http://hw8-app/version
  ```
- [ ] Объяснить, почему `build` остался на GitHub-hosted: `containerMode` не задан,
      dind в minikube не нужен, сборка в облаке уже кеширует слои

### 14. Идемпотентность и очистка

- [ ] Повторно запустить `./init.sh` — падать не должен
- [ ] Показать `./teardown.sh` и порядок удаления: сначала `HW8_RUNNER`, потом
      scale set, потом контроллер (finalizer'ы снимает контроллер, иначе зависнет)

---

## Шпаргалка

```bash
# Пайплайн
gh run list --workflow hw8-release.yml
gh run view <id>
gh run watch

# Теги и релизы
git fetch --tags && git tag -l
gh release list
gh release view v1.0.0

# Образ в GHCR
gh api /users/fastrapier/packages/container/hw8/versions \
  --jq '.[].metadata.container.tags'

# Задеплоенный тег
kubectl get deployment hw8-app -n k8s-hw8 \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl run curl-hw8 --rm -it --restart=Never -n k8s-hw8 \
  --image=curlimages/curl -- curl -s http://hw8-app/version

# Деплой другого тега
cd hw-8 && ./scripts/02-deploy.sh 1.0.0

# Свой раннер
kubectl get pods -n arc-systems
kubectl get pods -n arc-runners
kubectl get autoscalingrunnersets -n arc-runners
gh api repos/fastrapier/k8s-hw/actions/runners \
  --jq '.runners[] | "\(.name) \(.status)"'
gh variable list

# Прогон деплоя на своём раннере, без нового релиза
gh workflow run hw8-release.yml -f tag=1.0.0
gh run watch

# Очистить всё
./teardown.sh
```
