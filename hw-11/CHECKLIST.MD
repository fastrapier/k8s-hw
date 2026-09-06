# Чеклист для защиты ДЗ 11

## Подготовка (до защиты)

```bash
# секреты — один раз
security add-generic-password -a fastrapier -s grafana-hw11 -w 'пароль-админа' -U
security add-generic-password -a fastrapier -s smtp-hw11    -w 'smtp-токен'    -U
cp hw-11/.env.example hw-11/.env && $EDITOR hw-11/.env   # GRAFANA_SMTP_USER

minikube start
minikube tunnel          # отдельный терминал, не закрывать
cd hw-11 && ./init.sh    # ~10 минут
```

Проверить, что всё поднялось:

```bash
kubectl get pods -n k8s-hw11
```

---

## Порядок демонстрации

### 0. Инфраструктура

- [ ] Показать, что стек развёрнут:
  ```bash
  kubectl get pods -n k8s-hw11
  kubectl get svc -n k8s-hw11
  kubectl get ingress -n k8s-hw11
  ```
- [ ] Объяснить: «Один namespace `k8s-hw11`, пять helm-релизов, развёрнутых helmfile-ом»

---

## Часть 1. Helmfile и сбор метрик

### 1.1 Helmfile установлен и инициализирован

- [ ] Версия helmfile:
  ```bash
  helmfile version
  ```
- [ ] Плагины, доставленные `helmfile init` (нужен `diff` для `helmfile apply`):
  ```bash
  helm plugin list
  ```
- [ ] Показать `hw-11/scripts/01-helmfile-init.sh` — `brew install helmfile`,
      `helmfile init --force`, `minikube addons enable ingress`

### 1.2 Репозиторий и чарт для prometheus

- [ ] Показать `hw-11/helmfile.yaml.gotmpl`:
  - секция `repositories` — `prometheus-community`, `grafana`
  - релиз `kube-prometheus-stack` с пинованной версией `89.2.3`
  - `environments.default.values` — namespace и хосты в одном месте
  - `needs` — порядок установки релизов
- [ ] Объяснить выбор: **kube-prometheus-stack, а не голый чарт `prometheus`** —
      нужен Prometheus Operator и CRD `ServiceMonitor`, чтобы метрики ингресса
      добавлялись отдельным объектом, а не правкой `scrape_configs` в values
- [ ] Показать, что helmfile видит все релизы:
  ```bash
  cd hw-11 && helmfile list
  ```

### 1.3 Values для чарта prometheus

- [ ] Показать `hw-11/values/kube-prometheus-stack.yaml.gotmpl` и объяснить:
  - `serviceMonitorSelectorNilUsesHelmValues: false` — **главная строка**: без неё
    Prometheus не подхватит наш `ServiceMonitor`
  - `grafana.enabled: false` + `forceDeployDashboards: true` — Grafana отдельным
    релизом (часть 3), но дашборды кластера сохраняются
  - `kubeControllerManager/Scheduler/Proxy/Etcd: enabled: false` — в minikube они
    слушают только `127.0.0.1`, таргеты висели бы в DOWN
  - `retention: 24h`, ресурсы — под minikube
- [ ] Показать, что подстановка хостов работает:
  ```bash
  kubectl get ingress -n k8s-hw11
  ```

### 1.4 Метрики ингресса

- [ ] Показать свой чарт `hw-11/charts/ingress-metrics/`
- [ ] Объяснить две тонкости:
  1. Порт **10254** не объявлен в `containerPorts` деплоймента addon-а →
     `targetPort` задан числом
  2. `Service` обязан лежать в namespace контроллера (селектор работает только в своём
     namespace) → `Service` в `ingress-nginx`, `ServiceMonitor` в `k8s-hw11` с
     `namespaceSelector`
- [ ] Показать объекты в двух namespace:
  ```bash
  kubectl get svc ingress-metrics -n ingress-nginx
  kubectl get servicemonitor ingress-metrics -n k8s-hw11 -o yaml
  ```
- [ ] Показать, что контроллер реально отдаёт метрики:
  ```bash
  kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- \
    curl -s localhost:10254/metrics | grep nginx_ingress_controller_requests | head -5
  ```

### 1.5 Открыть веб-интерфейс

- [ ] Открыть **Prometheus**: http://prometheus-hw11.local
- [ ] Status → Targets: показать таргет `ingress-metrics` в состоянии **UP**
- [ ] Status → Configuration: показать, что джоба появилась из ServiceMonitor
- [ ] Открыть **Alertmanager**: http://alertmanager-hw11.local

### 1.6 Сделать запрос на метрики nginx

- [ ] Запустить скрипт (он сам генерирует трафик — без запросов метрики-счётчика нет):
  ```bash
  ./scripts/03-check-metrics.sh
  ```
- [ ] Затем **в UI Prometheus** (http://prometheus-hw11.local/graph) выполнить руками:
  ```promql
  nginx_ingress_controller_requests
  ```
  ```promql
  sum by (ingress, status) (nginx_ingress_controller_requests)
  ```
  ```promql
  sum(rate(nginx_ingress_controller_requests[1m]))
  ```
  ```promql
  histogram_quantile(0.95, sum by (le) (rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])))
  ```
- [ ] Пока идёт демонстрация — в отдельном терминале нагрузить ингресс и показать, как
      график `rate(...)` растёт:
  ```bash
  while true; do curl -s -o /dev/null http://prometheus-hw11.local/-/ready; done
  ```

---

## Часть 2. Сбор логов

### 2.1 Loki установлен через helmfile

- [ ] Показать релиз `loki` в `helmfile.yaml.gotmpl` (версия `7.3.0`)
- [ ] Показать `hw-11/values/loki.yaml` и объяснить:
  - `deploymentMode: SingleBinary` — один StatefulSet вместо read/write/backend,
    иначе в minikube поднялось бы больше десятка подов
  - `loki.storage.type: filesystem` + PVC — без minio/S3
  - `replication_factor: 1` — реплицировать некуда, узел один
  - `schemaConfig` с `tsdb`/`v13` — чарт требует задать схему явно
  - `auth_enabled: false` — без мультиарендности не нужен `X-Scope-OrgID`
- [ ] Показать поды и PVC:
  ```bash
  kubectl get statefulset loki -n k8s-hw11
  kubectl get pvc -n k8s-hw11
  kubectl get svc -n k8s-hw11 | grep loki
  ```
- [ ] Объяснить разницу: `loki-gateway:80` (nginx-прокси, единая точка входа) и
      `loki:3100` (сам singleBinary)

### 2.2 Promtail установлен через helmfile

- [ ] Показать релиз `promtail` с `needs: [loki]` и `hw-11/values/promtail.yaml.gotmpl`
- [ ] Обратить внимание: адрес отправки — именно `loki-gateway`, а не `loki:3100`
- [ ] Показать DaemonSet:
  ```bash
  kubectl get daemonset promtail -n k8s-hw11
  kubectl logs daemonset/promtail -n k8s-hw11 --tail=20
  ```
- [ ] Упомянуть: promtail deprecated в пользу Grafana Alloy, поставлен по заданию

### 2.3 Логи реально доходят

- [ ] Запустить скрипт:
  ```bash
  ./scripts/04-check-logs.sh
  ```
  Показывает метки Loki, значения метки `namespace` и сами строки логов
- [ ] Показать в **Grafana Explore** (http://grafana-hw11.local/explore), datasource
      **Loki**:
  ```logql
  {namespace="k8s-hw11"}
  ```
  ```logql
  {namespace="ingress-nginx"}
  ```
  — это тот же трафик, что породил метрики в части 1
  ```logql
  {namespace="k8s-hw11"} |= "error"
  ```
- [ ] Показать, что promtail отдаёт и свои метрики в Prometheus:
  ```promql
  promtail_sent_entries_total
  ```

---

## Часть 3. Grafana и алертинг

### 3.1 SMTP-токен получен

- [ ] Объяснить: нужен **пароль приложения**, а не основной пароль аккаунта — с 2FA
      основной пароль по SMTP не работает
- [ ] Показать, где он лежит (значение не показывать):
  ```bash
  security find-generic-password -a fastrapier -s smtp-hw11 -w | head -c 4
  ```
- [ ] Показать `hw-11/.env.example` — какие переменные нужны, значений в репозитории нет
- [ ] Показать `load_env()` в `hw-11/scripts/common.sh` — Keychain + `.env`, падение с
      подсказкой, если чего-то нет

### 3.2 Grafana установлена

- [ ] Показать релиз `grafana` (версия `10.5.15`) с `needs` на stack и loki
- [ ] Показать `hw-11/values/grafana.yaml.gotmpl`:
  - `adminPassword: {{ requiredEnv "GRAFANA_ADMIN_PASSWORD" }}` — установка с пустым
    паролем невозможна по построению
  - три datasource с фиксированными `uid`
  - дашборды по `gnetId` + sidecar для дашбордов кластера
- [ ] **Показать, что SMTP-токен внутри кластера лежит в Secret, а не в ConfigMap**:
  ```bash
  kubectl get secret grafana-env -n k8s-hw11 -o jsonpath='{.data}' | head -c 80; echo
  kubectl get configmap grafana -n k8s-hw11 -o yaml | grep -A3 '\[smtp\]'
  ```
  В ConfigMap стоит `password = $__env{GF_SMTP_PASSWORD}` — подстановка из Secret

### 3.3 Зайти в веб-интерфейс

- [ ] Открыть http://grafana-hw11.local, войти как `admin`
  ```bash
  security find-generic-password -a fastrapier -s grafana-hw11 -w
  ```
- [ ] Connections → Data sources: показать **Prometheus**, **Loki**, **Alertmanager** —
      все provisioned (read-only)
- [ ] Нажать **Test** у Prometheus и Loki — обе зелёные
- [ ] Dashboards → папка **hw-11**: открыть **Node Exporter Full** (1860) — метрики узла
- [ ] Открыть **NGINX Ingress controller** (9614) — метрики ингресса из части 1
- [ ] Показать дашборды кластера, приехавшие из kube-prometheus-stack через sidecar
- [ ] Explore → Loki — логи из части 2

### 3.4 Настроить контакты и алертинг

- [ ] Alerting → **Contact points**: показать `email-hw11` (тип email, адрес из
      `$ALERT_EMAIL`, provisioned)
- [ ] Alerting → **Notification policies**: дефолтная политика уходит на `email-hw11`,
      `group_by: [grafana_folder, alertname]`
- [ ] Alerting → **Alert rules**: показать два правила в папке `hw-11`:
  - `Ingress: RPS выше 1 запроса в секунду` (`for: 1m`) — демонстрационное
  - `Ingress: доля 5xx выше 5%` (`for: 2m`) — осмысленное
- [ ] Открыть правило и объяснить, что правило Grafana — **граф**, а не строка PromQL:
      запрос `A` (datasource `prometheus`) + порог `C` (`__expr__`, `type: threshold`),
      `condition: C`
- [ ] Объяснить `noDataState: OK` и `clamp_min(..., 0.001)` в правиле 5xx — при нулевом
      трафике `0/0 = NaN`, без clamp правило ушло бы в NoData

### 3.5 Тестовое письмо и реальное срабатывание

- [ ] **Синтетическое письмо** — кнопкой в UI:
      Alerting → Contact points → `email-hw11` → Edit → **Test** → Send test notification
- [ ] Объяснить, почему именно кнопкой: HTTP-эндпоинт
      `/api/alertmanager/grafana/config/api/v1/receivers/test` в Grafana 12 удалён и
      отвечает `410 Gone`
- [ ] **Реальное срабатывание** — прогнать всю цепочку метрика → правило → политика →
      контакт → SMTP → письмо:
  ```bash
  ./scripts/05-test-alert.sh          # ~3 минуты
  ```
- [ ] Пока скрипт работает, показать в UI Alerting → Alert rules, как правило
      `hw11-ingress-rps` проходит **Normal → Pending → Alerting**
- [ ] Показать письмо в почте
- [ ] Если письма нет — показать диагностику:
  ```bash
  kubectl logs deployment/grafana -n k8s-hw11 -c grafana | grep -i smtp
  ```

---

## Идемпотентность и очистка

- [ ] Показать, что повторный запуск ничего не ломает:
  ```bash
  cd hw-11 && helmfile diff        # пусто — кластер уже в описанном состоянии
  ./init.sh                        # проходит повторно
  ```
- [ ] Объяснить `teardown.sh`: релизы, PVC, `/etc/hosts`; CRD Prometheus Operator
      остаются, потому что общие на весь кластер — сносятся только `./teardown.sh --crds`

---

## Шпаргалка

```bash
# состояние
kubectl get pods -n k8s-hw11
cd hw-11 && helmfile list && helmfile diff

# UI
open http://prometheus-hw11.local
open http://alertmanager-hw11.local
open http://grafana-hw11.local
security find-generic-password -a fastrapier -s grafana-hw11 -w   # пароль admin

# проверки по частям
./scripts/03-check-metrics.sh   # часть 1
./scripts/04-check-logs.sh      # часть 2
./scripts/05-test-alert.sh      # часть 3

# нагрузить ингресс (для графиков и алерта)
while true; do curl -s -o /dev/null http://prometheus-hw11.local/-/ready; done

# очистка
./teardown.sh
```
