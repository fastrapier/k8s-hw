# Чеклист для защиты ДЗ 9

## Подготовка

```bash
security add-generic-password -a fastrapier -s ghcr.io -w YOUR_GITHUB_TOKEN -U   # один раз
minikube start
minikube tunnel        # отдельный терминал
cd hw-9 && ./init.sh   # ~6-8 минут (Vault → интеграция → сборка → деплой)
```

---

# Часть 1. Установка werf и рефакторинг

### 1. werf установлен

- [ ] ```bash
  werf version
  ```

### 2. Структура werf-проекта

- [ ] Показать `werf.yaml` — `project: hw9` и три образа:
  ```bash
  cat werf.yaml
  ```
- [ ] Объяснить: «Один файл вместо Makefile на 300 строк. werf сам собирает, пушит
  и деплоит, теги считает по содержимому».

### 3. Исходники проекта внутри werf-проекта

- [ ] Показать дерево: `main.go`, `cmd/cronjob`, `internal/`, `migrations/`, `docker/`, `.helm/`
  ```bash
  ls -1
  ```
- [ ] Собрать и прогнать тесты:
  ```bash
  go build ./... && go vet ./... && go test ./...
  ```
- [ ] Объяснить: «Код, Dockerfile-ы и чарт лежат в одном проекте и версионируются вместе —
  werf собирает образы из того же git-состояния, из которого рендерит чарт».

### 4. Helm submodules

- [ ] Показать `dependencies` и сабчарты:
  ```bash
  cat .helm/Chart.yaml
  ls .helm/charts
  helm dependency list .helm
  ```
- [ ] Объяснить три вещи:
  - сабчарты — директории в `.helm/charts/`, helm грузит их сам, качать нечего;
  - `condition: postgres.enabled` даёт выключатель;
  - `Chart.lock` (от `helm dependency update`) нужен, чтобы werf не писал
    `Cannot automatically download chart dependencies...` в stdout.
- [ ] Показать, что выключатель работает:
  ```bash
  werf render --dev --stub-tags --set postgres.enabled=false \
    --set global.secrets.postgres.username=u --set global.secrets.postgres.password=p \
    --set global.secrets.postgres.database=d \
    --set global.secrets.backend.username=bu --set global.secrets.backend.password=bp \
    | grep '^# Source'
  ```
  Останутся только шаблоны backend.

### 5. Глобальные values

- [ ] Показать `global` в `.helm/values.yaml`:
  ```bash
  sed -n '1,45p' .helm/values.yaml
  ```
- [ ] Показать, как сабчарт backend читает координаты БД из `global` (хелпер `backend.postgresEnv`):
  ```bash
  sed -n '/backend.postgresEnv/,/end }}/p' .helm/charts/backend/templates/_helpers.tpl
  ```
- [ ] Объяснить: «Порт, имена сервисов, ConfigMap и Secret заданы один раз. Сабчарты
  не знают друг о друге — общаются через `global`».

### 6. Образы werf в чарте

- [ ] Показать хелпер и его использование:
  ```bash
  sed -n '/define "backend.image"/,/end }}/p' .helm/charts/backend/templates/_helpers.tpl
  grep -n 'backend.image' .helm/charts/backend/templates/*.yaml
  ```
- [ ] Объяснить разницу уровней: в родительском чарте `.Values.werf.image.app`,
  в сабчарте только `.Values.global.werf.images.app.ref` — `.Values.werf` внутрь не прокидывается.
- [ ] Показать реальные теги в задеплоенных подах:
  ```bash
  kubectl get deployment backend -n k8s-hw9 -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
  ```

---

# Часть 2. Интеграция с Vault и деплой

### 7. Vault: секреты, политика, AppRole

- [ ] Показать секреты (docker-токен — только маску!):
  ```bash
  kubectl exec vault-0 -n k8s-hw9 -- vault kv get secret/postgres
  kubectl exec vault-0 -n k8s-hw9 -- vault kv get secret/backend
  kubectl exec vault-0 -n k8s-hw9 -- vault kv get -field=username secret/docker
  ```
- [ ] Показать политику и роль:
  ```bash
  kubectl exec vault-0 -n k8s-hw9 -- vault policy read app-policy
  kubectl exec vault-0 -n k8s-hw9 -- vault read auth/approle/role/app-role
  ```
- [ ] Объяснить: «docker-токен GHCR берётся из macOS Keychain и кладётся в Vault. Дальше
  и `werf cr login`, и `imagePullSecret` читают его только из Vault».

### 8. Скрипт интеграции — четыре шага

- [ ] Показать скрипт целиком:
  ```bash
  cat scripts/02-vault-integration.sh
  ```
- [ ] Пройти по шагам:
  1. **AppRole login** — `role_id` + `secret_id` → client token; дальше все чтения под ним,
     не под root; `port-forward` 8200 нужен, чтобы `vals` видел Vault с хоста;
  2. **docker-токен** → `WERF_PASSWORD=... werf cr login ghcr.io` (пароль переменной
     окружения, не аргументом — аргументы видны в `ps`);
  3. **секреты приложения** → `vals eval -f secret-values.tpl.yaml` в tmp-файл;
  4. **деплой** → `werf converge --values <tmp> --set-docker-config-json-value`.
- [ ] Оговорить трактовку: презентации нет, «аналогично презентации» реализовано как один
  скрипт Vault → registry → секреты → converge (написано и в README).

### 9. В репозитории нет секретов

- [ ] Показать шаблон — только ссылки:
  ```bash
  cat secret-values.tpl.yaml
  ```
- [ ] Показать, что отрендеренного файла нет и он в `.gitignore`:
  ```bash
  cat .gitignore
  ls secret-values.rendered.yaml 2>&1     # No such file — удалён по trap
  git status --short
  ```
- [ ] Показать, что чарт без секретов не рендерится:
  ```bash
  werf render --dev --stub-tags
  ```
  Ожидаемо: `global.secrets.postgres.username не задан: запустите scripts/02-vault-integration.sh`

### 10. Отдельный docker config — неочевидная причина

- [ ] Показать, что в пользовательском конфиге кред нет:
  ```bash
  cat ~/.docker/config.json
  ```
  `credsStore: desktop` — креды в Keychain, в файле пусто.
- [ ] Объяснить: поэтому скрипт логинится в `WERF_DOCKER_CONFIG=$(mktemp -d)`, иначе
  `--set-docker-config-json-value` собрал бы пустой `imagePullSecret` и поды не скачали бы образы.
- [ ] Показать получившийся pull secret:
  ```bash
  kubectl get secret ghcr-pull-secret -n k8s-hw9 -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
  ```

### 11. Задеплоенный werf-проект

- [ ] Всё запущено:
  ```bash
  kubectl get pods,svc,ingress,cronjob,statefulset -n k8s-hw9
  helm list -n k8s-hw9
  ```
- [ ] Миграции прошли (Job — helm-хук `post-install,post-upgrade`):
  ```bash
  kubectl logs job/backend-migrations -n k8s-hw9
  ```
- [ ] Секреты доехали из Vault в поды:
  ```bash
  kubectl exec vault-0 -n k8s-hw9 -- vault kv get -field=password secret/backend
  curl -s http://app-hw9.local/secret
  ```
  Значения должны совпасть.
- [ ] Приложение и БД работают:
  ```bash
  curl -s http://app-hw9.local/healthz
  curl -s -X POST http://app-hw9.local/db/requests
  ```
- [ ] CronJob пишет в БД (подождать минуту):
  ```bash
  kubectl get jobs -n k8s-hw9
  kubectl logs -l app.kubernetes.io/component=cron -n k8s-hw9 --tail=5
  ```

### 12. Идемпотентность и очистка

- [ ] Повторный `werf converge` — no changes:
  ```bash
  ./scripts/02-vault-integration.sh
  ```
- [ ] Объяснить: «`init.sh` можно запускать повторно, `teardown.sh` убирает релиз, Vault,
  PVC и записи в /etc/hosts».

---

## Шпаргалка

```bash
kubectl get pods -n k8s-hw9
kubectl logs deployment/backend -n k8s-hw9 --tail=20
kubectl logs job/backend-migrations -n k8s-hw9

werf render --dev --stub-tags                      # упадёт без секретов — так и надо
werf dismiss --release hw9 --namespace k8s-hw9

./teardown.sh
kubectl delete namespace k8s-hw9
```
