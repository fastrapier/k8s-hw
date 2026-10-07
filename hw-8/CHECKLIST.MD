# Чеклист для защиты ДЗ 8

## Быстрая шпаргалка для экзамена

Проверенный стенд: профиль `k8s-exam`, namespace приложения `k8s-hw8`,
раннер `hw8-minikube`, опубликованный образ `ghcr.io/fastrapier/hw8:1.0.0`.

### 1. Выбрать стенд и проверить его

```bash
cd /Users/notwork/dopki/k8s-hw/hw-8
export MINIKUBE_PROFILE=k8s-exam
kubectl config use-context k8s-exam

kubectl get pods -n k8s-hw8
kubectl get pods -n arc-systems
kubectl get pods -n arc-runners
gh variable list --repo fastrapier/k8s-hw
gh api repos/fastrapier/k8s-hw/actions/runners \
  --jq '.runners[] | "\(.name) \(.status)"'
```

Ожидаем две готовые реплики приложения, готовые контроллер/listener,
раннер `online` и `HW8_RUNNER=hw8-minikube`.

### 2. Показать выполненный полный цикл CI/CD

```bash
gh release view v1.0.0 --repo fastrapier/k8s-hw
gh run view 37623872269 --repo fastrapier/k8s-hw
gh run view 37623872269 --job 112801315675 --log --repo fastrapier/k8s-hw
docker buildx imagetools inspect ghcr.io/fastrapier/hw8:1.0.0
```

В [проверенном прогоне](https://github.com/fastrapier/k8s-hw/actions/runs/37623872269)
успешны все три джобы: версия → сборка и публикация образа → деплой.
В логе деплоя показать `runs-on: hw8-minikube`,
`RUNNER_ENVIRONMENT: self-hosted`, `внутри кластера: да`.
У образа — платформы `linux/amd64` и `linux/arm64`.

### 3. Повторить деплой вживую

```bash
gh workflow run hw8-release.yml --ref main -f tag=1.0.0 \
  --repo fastrapier/k8s-hw
gh run watch --repo fastrapier/k8s-hw
```

Выбрать новый прогон `workflow_dispatch` для `main`. Он деплоит готовый тег:
`release` и `build` пропущены, `deploy` выполнен на ARC-раннере.
Во втором терминале можно наблюдать его под:

```bash
kubectl --context=k8s-exam get pods -n arc-runners -w
```

После джобы под раннера удаляется, ARC создаёт новый ожидающий под.

### 4. Подтвердить образ, версию и коммит

```bash
kubectl get deployment hw8-app -n k8s-hw8 \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl exec -n k8s-hw8 deployment/hw8-app \
  -- wget -qO- http://127.0.0.1:8080/version
```

Для релиза `1.0.0` ожидаемый ответ:

```json
{"version":"1.0.0","commit":"ee7edd6f80b5f26e78bdf4008a5d9c16a3fb850e","env_version":"1.0.0"}
```

### 5. Открыть приложение в браузере

В отдельном терминале:

```bash
kubectl --context=k8s-exam port-forward -n k8s-hw8 svc/hw8-app 8088:80
```

Открыть <http://127.0.0.1:8088/version> или <http://127.0.0.1:8088/healthz>.
Этот способ не требует туннеля или Ingress; CI-деплой использует чарт с
`ingress.enabled=false`.

### Если после перезапуска стенда раннер не готов

```bash
minikube start -p k8s-exam
./scripts/03-deploy-runner.sh
```

Первая загрузка образа раннера на нашем стенде заняла 7 минут 38 секунд;
скрипт ждёт до 10 минут. Приложение при необходимости восстанавливается
командой `./scripts/02-deploy.sh 1.0.0`.

Если тег совпал с ранее загруженным локальным образом, а `/version` показывает
старый коммит, принудительно скачать опубликованный образ:

```bash
kubectl patch deployment hw8-app -n k8s-hw8 --type=strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","imagePullPolicy":"Always"}]}}}}'
kubectl rollout status deployment/hw8-app -n k8s-hw8 --timeout=300s
```

---

## Подготовка

```bash
export MINIKUBE_PROFILE=k8s-exam
minikube start -p k8s-exam
kubectl config use-context k8s-exam
minikube tunnel -p k8s-exam     # отдельный терминал, если нужен Ingress
git fetch --tags
cd hw-8 && ./init.sh 1.0.0     # из корня репозитория: деплой + раннер
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
- [ ] Объяснить про merge-коммиты: «Сам `Merge pull request #N` не влияет на
      версию, но при обычном merge учитываются Conventional Commits внутри PR.
      При squash итоговое сообщение должно иметь conventional-формат»

### 2. semantic-release — вычисление версии вживую

- [ ] Показать dry-run локально:
  ```bash
  cd hw-8
  export GITHUB_TOKEN=$(gh auth token)
  ./scripts/01-release-dry-run.sh
  ```
- [ ] Показать рассчитанную версию; после релиза без новых подходящих коммитов
      нормален результат «релиз не требуется». Dry-run не создаёт тег или Release.
- [ ] Если версия рассчитана, показать файл из текущей директории `hw-8`:
  ```bash
  cat .version
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
- [ ] Через Ingress после локального `02-deploy.sh` (нужен `minikube tunnel`):
  ```bash
  curl --resolve hw8.local:80:127.0.0.1 http://hw8.local/version
  ```
  После CI-деплоя Ingress отключён; для браузера использовать port-forward
  из быстрой шпаргалки выше.
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
- [ ] Объяснить fallback: `ubuntu-latest` выбирается, только если `HW8_RUNNER`
      не задана. Если переменная задана, а minikube выключен, джоба ждёт раннер
      в очереди.

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

## Команды для быстрого показа

См. [шпаргалку в начале файла](#быстрая-шпаргалка-для-экзамена).
