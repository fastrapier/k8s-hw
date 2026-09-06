# Чеклист для защиты ДЗ 8

## Подготовка

```bash
minikube start
minikube tunnel                # отдельный терминал
git fetch --tags
cd hw-8 && ./init.sh           # деплой последнего тега, ~1 минута
```

---

## Порядок демонстрации

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

- [ ] Показать шаг `Kubeconfig` в джобе `deploy` и `::warning::` в логах
- [ ] Объяснить: «GitHub-hosted раннер в облаке не имеет сетевого доступа к minikube
      на ноутбуке; поэтому шаг честно предупреждает и не падает»
- [ ] Объяснить, что это решает часть 2: self-hosted раннер внутри кластера,
      после чего в джобе меняется только `runs-on`

### 11. Идемпотентность

- [ ] Повторно запустить `./init.sh` — падать не должен
- [ ] Показать `./teardown.sh`

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

# Очистить всё
./teardown.sh
```
