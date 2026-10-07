# ДЗ 11 — Мониторинг

Стек мониторинга в minikube, развёрнутый одной командой через **helmfile**: Prometheus
собирает метрики (включая метрики ингресса), Loki и promtail — логи, Grafana показывает
и то и другое и отправляет алерты на почту через SMTP.

## Архитектура

```
                          minikube tunnel ──► 127.0.0.1:80
                                                   │
┌──────────────────────────── Kubernetes (minikube) ┼──────────────────────────────────┐
│                                                   │                                  │
│  namespace: ingress-nginx                         ▼                                  │
│   ┌──────────────────────────────┐   Ingress: prometheus-hw11.local                  │
│   │  ingress-nginx-controller    │            alertmanager-hw11.local                │
│   │  (minikube addon ingress)    │            grafana-hw11.local                     │
│   │                              │                                                   │
│   │  :80/:443  трафик            │                                                   │
│   │  :10254    /metrics ◄────────┼───┐  --enable-metrics=true по умолчанию            │
│   └──────────────────────────────┘   │                                               │
│   ┌──────────────────────────────┐   │ Service ingress-metrics :10254                │
│   │ Service ingress-metrics      │───┘ (свой чарт charts/ingress-metrics)            │
│   └──────────────┬───────────────┘                                                   │
│ ═══════════════════════════════════════════════════════════════════════════════════ │
│  namespace: k8s-hw11               │ ServiceMonitor (namespaceSelector: ingress-nginx)│
│                                     ▼                                                │
│   ┌───────────────────────────────────────┐                                          │
│   │ Prometheus  (kube-prometheus-stack)   │  ServiceMonitor-ы:                       │
│   │  Operator + CRD ServiceMonitor        │◄── node-exporter (DaemonSet)              │
│   │  retention 24h, scrape 30s            │◄── kube-state-metrics                     │
│   │                                       │◄── kubelet, apiserver, coredns            │
│   └───────┬──────────────────────┬────────┘◄── promtail                               │
│           │ 30 PrometheusRule    │                                                    │
│           ▼                      │                                                    │
│   ┌────────────────┐             │ datasource Prometheus                              │
│   │  Alertmanager  │             │                                                    │
│   └────────────────┘             ▼                                                    │
│                        ┌─────────────────────────────────┐                            │
│                        │ Grafana                         │   datasource Loki          │
│                        │  дашборды 1860 / 9614 / 13639   │◄────────────┐              │
│                        │  + дашборды kube-prometheus     │             │              │
│                        │  contact point  email-hw11      │   ┌─────────┴──────────┐   │
│                        │  rules  hw11-ingress-rps / 5xx  │   │  loki-gateway :80  │   │
│                        └───────────────┬─────────────────┘   └─────────┬──────────┘   │
│                                        │ SMTP                          │              │
│                                        ▼                    ┌─────────▼──────────┐   │
│                             smtp.gmail.com:587              │  loki              │   │
│                                        │                    │  SingleBinary      │   │
│                                        ▼                    │  filesystem, 72h   │   │
│                                     email                   └─────────▲──────────┘   │
│                                                                       │ push          │
│                                                             ┌─────────┴──────────┐   │
│                                                             │ promtail DaemonSet │   │
│                                                             │ читает /var/log/pods│  │
│                                                             └────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## Структура проекта

```
hw-11/
├── init.sh                       # Точка входа: 01 → 02
├── teardown.sh [--crds]          # Полная очистка (CRD — только по флагу)
├── TASK.MD                       # Задание
├── CHECKLIST.MD                  # Чеклист для защиты
├── .env.example                  # Какие env нужны (без значений)
│
├── helmfile.yaml.gotmpl          # Все 5 релизов: репозитории, версии, порядок
├── values/
│   ├── kube-prometheus-stack.yaml.gotmpl   # Prometheus, Alertmanager, exporters
│   ├── ingress-metrics.yaml.gotmpl         # namespace контроллера ингресса
│   ├── loki.yaml                           # SingleBinary + filesystem
│   ├── promtail.yaml.gotmpl                # адрес loki-gateway
│   └── grafana.yaml.gotmpl                 # datasources, дашборды, SMTP, алертинг
│
├── charts/ingress-metrics/       # Свой мини-чарт: метрики ингресса
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── service.yaml          # Service :10254 в namespace ingress-nginx
│       └── servicemonitor.yaml   # ServiceMonitor в k8s-hw11
│
└── scripts/
    ├── common.sh                 # Общие функции, загрузка env, port-forward
    ├── lib/render.py             # Форматирование JSON-ответов API
    ├── 01-helmfile-init.sh       # brew install helmfile, helmfile init, addon ingress
    ├── 02-deploy.sh              # helmfile apply + /etc/hosts + URL
    ├── 03-check-metrics.sh       # Часть 1: запрос метрик nginx
    ├── 04-check-logs.sh          # Часть 2: логи в Loki
    └── 05-test-alert.sh          # Часть 3: контакты и алертинг
```

## Быстрый старт

Для проверки в профиле `k8s-exam` без отправки писем:

```bash
export MINIKUBE_PROFILE=k8s-exam
export GRAFANA_SMTP_ENABLED=false
cd hw-11
./scripts/01-helmfile-init.sh
./scripts/02-deploy.sh
./scripts/03-check-metrics.sh
./scripts/04-check-logs.sh
./scripts/05-test-alert.sh
```

В отдельном терминале должен работать `minikube tunnel -p k8s-exam`.
Пароль Grafana при первом запуске создаётся в Keychain (`grafana-hw11`), затем
переиспользуется. `.env` для этого режима не нужен; если он существует,
`GRAFANA_SMTP_ENABLED=false` задайте в нём, поскольку файл имеет приоритет над окружением.

SMTP по умолчанию выключен. Правила вычисляются, а уведомления с меткой `hw=11`
заглушены круглосуточным mute timing `hw11-no-email` в дочерней политике.
`05-test-alert.sh` пропускает тест письма и требует состояние `firing` у правила RPS.
Это проверка метрик и алертинга; отправка письма из задания остаётся непроверенной.
[Механизм mute timings Grafana](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/mute-timings/)
сохраняет вычисление правил.

Для полной SMTP-проверки: скопируйте `.env.example` в `.env`, задайте
`GRAFANA_SMTP_ENABLED=true`, SMTP-логин и адрес получателя, сохраните пароль
приложения в Keychain `smtp-hw11`, затем повторите `02-deploy.sh` и `05-test-alert.sh`.
Полный запуск всех шагов: `./init.sh`.

## Доступ к UI

| Сервис | URL | Доступ |
|---|---|---|
| Prometheus | http://prometheus-hw11.local | без авторизации |
| Alertmanager | http://alertmanager-hw11.local | без авторизации |
| Grafana | http://grafana-hw11.local | `admin` / `$GRAFANA_ADMIN_PASSWORD` |

Loki наружу не публикуется — он нужен только Grafana внутри кластера. Для ручных
запросов скрипт `04-check-logs.sh` поднимает port-forward на `svc/loki-gateway`.

> Все три хоста прописываются в `/etc/hosts` скриптом `02-deploy.sh` и требуют
> запущенного `minikube tunnel`.

## Что такое helmfile и зачем он здесь

`helm` умеет ставить один чарт за раз, и состояние «какие релизы, каких версий, с какими
values составляют стек» живёт в истории команд или в bash-скрипте. `helmfile` описывает
это декларативно в одном файле: репозитории, релизы, пинованные версии чартов, values
и зависимости между релизами.

Практическая польза именно в этом ДЗ:

- **Один вход.** `helmfile apply` разворачивает все пять релизов; повторный запуск —
  идемпотентен и показывает diff вместо слепого переустановления.
- **Порядок через `needs`.** `ingress-metrics` создаёт `ServiceMonitor` — это CRD из
  Prometheus Operator, поэтому релиз обязан идти после `kube-prometheus-stack`. То же
  с `promtail` после `loki` и `grafana` после обоих. В обычном helm это был бы
  комментарий в README, здесь — машиночитаемое ограничение.
- **Шаблонизация values.** Имя namespace и хосты заданы один раз в
  `environments.default.values`, а values-файлы с расширением `.gotmpl` подставляют их
  через `{{ .Values.hosts.grafana }}`. Секреты берутся из окружения через
  `requiredEnv` — деплой упадёт с понятной ошибкой, а не установит Grafana с пустым
  паролем.

Файл называется `helmfile.yaml.gotmpl`, а не `helmfile.yaml`: начиная с helmfile v1
шаблонизация самого helmfile включается именно расширением `.gotmpl`. С обычным именем
`{{ .Values.namespace }}` в секции `releases` ломает парсинг YAML.

Полезные команды:

```bash
cd hw-11
helmfile list                     # какие релизы описаны
helmfile diff                     # что изменится при apply
helmfile apply                    # привести кластер к описанному состоянию
helmfile template                 # отрендерить манифесты, не касаясь кластера
helmfile destroy                  # удалить все релизы
helmfile -l name=grafana apply    # только один релиз
```

## Релизы и ключевые values

| Релиз | Чарт | Версия | Namespace |
|---|---|---|---|
| kube-prometheus-stack | prometheus-community/kube-prometheus-stack | 89.2.3 | k8s-hw11 |
| ingress-metrics | ./charts/ingress-metrics | 0.1.0 (свой) | k8s-hw11 |
| loki | grafana/loki | 7.3.0 | k8s-hw11 |
| promtail | grafana/promtail | 6.17.1 | k8s-hw11 |
| grafana | grafana/grafana | 10.5.15 | k8s-hw11 |

### kube-prometheus-stack, а не чарт `prometheus`

Задание говорит «добавить чарт для prometheus». Взят `kube-prometheus-stack`, а не голый
`prometheus-community/prometheus`, потому что дальше по заданию нужно **добавить метрики
ингресса**. Голый чарт настраивается статическими `scrape_configs` в values: чтобы
добавить новый таргет, надо править values Prometheus и перезапускать релиз.
`kube-prometheus-stack` приносит Prometheus Operator и CRD `ServiceMonitor` — новый
источник метрик описывается отдельным объектом в кластере, и Prometheus подхватывает его
сам. Именно так сделан релиз `ingress-metrics`.

Плюс в комплекте сразу идут node-exporter, kube-state-metrics, Alertmanager и 30 групп
готовых `PrometheusRule` — то, что для голого чарта пришлось бы собирать руками.

Ключевые values (`values/kube-prometheus-stack.yaml.gotmpl`):

```yaml
prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false
```

Без этого Prometheus сужает выбор `ServiceMonitor`-ов до тех, что помечены метками самого
чарта, и наш `ingress-metrics` останется незамеченным. То же для `podMonitor`, `rule`,
`probe` и `scrapeConfig`.

```yaml
grafana:
  enabled: false
  forceDeployDashboards: true
```

Grafana ставится **отдельным релизом** — это часть 3 задания, и её values (SMTP,
алертинг, datasources) логичнее держать в своём файле, а не внутри секции `grafana:`
чужого чарта. Но дашборды кластера, которые кладёт stack, терять не хочется:
`forceDeployDashboards: true` создаёт их ConfigMap-ы даже при отключённой Grafana,
а sidecar внешней Grafana подхватывает их по метке `grafana_dashboard`.

```yaml
kubeControllerManager.enabled: false
kubeScheduler.enabled: false
kubeProxy.enabled: false
kubeEtcd.enabled: false
```

В minikube эти компоненты control plane слушают только на `127.0.0.1` внутри узла, и
Prometheus их не соскрейпит: таргеты вечно висят в `DOWN`, а правила алертов по ним
шумят. Отключены и сами таргеты, и соответствующие группы `defaultRules`.

### Метрики ингресса

Ingress-nginx отдаёт метрики на порту **10254** — это внутренний HTTP-сервер контроллера,
на нём же живут `/healthz` (его используют пробы) и `/nginx_status`. Флаг
`--enable-metrics` по умолчанию `true`, и манифест addon-а minikube его не выключает,
так что метрики уже есть — не хватает только того, кто их соберёт.

Две тонкости, из-за которых понадобился свой мини-чарт:

1. **Порт 10254 не объявлен в `containerPorts`** деплоймента addon-а (там только 80, 443
   и webhook). Поэтому `Service` задаёт `targetPort: 10254` числом, а не именем порта.
2. **Service обязан лежать в namespace контроллера.** Селектор `Service` сопоставляет
   поды только в своём namespace, поэтому `Service` создаётся в `ingress-nginx`, а
   `ServiceMonitor` остаётся в `k8s-hw11` рядом с Prometheus и смотрит на чужой
   namespace через `namespaceSelector`. Один helm-релиз, два namespace.

Селектор берёт метки из манифеста addon-а
(`deploy/addons/ingress/ingress-deploy.yaml` в репозитории minikube):

```yaml
app.kubernetes.io/name: ingress-nginx
app.kubernetes.io/instance: ingress-nginx
app.kubernetes.io/component: controller
```

Проверка: `./scripts/03-check-metrics.sh` — скрипт сначала генерирует ~40 запросов через
ингресс (без трафика метрики-счётчика просто не существует), потом показывает
состояние таргета и выполняет запросы.

### PromQL для демонстрации

```promql
# сырой счётчик запросов, разложенный по ingress и коду ответа
nginx_ingress_controller_requests
sum by (ingress, status) (nginx_ingress_controller_requests)

# запросов в секунду
sum(rate(nginx_ingress_controller_requests[1m]))
sum by (ingress) (rate(nginx_ingress_controller_requests[1m]))

# 95-й перцентиль времени ответа
histogram_quantile(0.95, sum by (le) (rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])))

# доля 5xx (clamp_min спасает от 0/0 при нулевом трафике)
sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
  / clamp_min(sum(rate(nginx_ingress_controller_requests[5m])), 0.001)

# состояние самого nginx
nginx_ingress_controller_nginx_process_connections
nginx_ingress_controller_config_last_reload_successful
```

### loki

Режим **SingleBinary**: один StatefulSet вместо трёх групп read/write/backend. Для
minikube это единственный разумный вариант — распределённый режим по умолчанию поднимает
больше десятка подов и требует S3-совместимое хранилище.

Ключевые values (`values/loki.yaml`):

- `loki.storage.type: filesystem` + `singleBinary.persistence` — чанки и индекс на PVC,
  без minio и S3;
- `loki.commonConfig.replication_factor: 1` — реплицировать некуда, узел один;
- `loki.schemaConfig` с `store: tsdb` / `schema: v13` — актуальная схема; чарт требует её
  задать явно, иначе падает на валидации;
- `loki.auth_enabled: false` — без мультиарендности не нужен заголовок `X-Scope-OrgID`
  ни в promtail, ни в datasource Grafana;
- `chunksCache`/`resultsCache`/`minio`/`lokiCanary`/`test` отключены — memcached и
  S3-хранилище для filesystem-режима избыточны;
- `write/read/backend.replicas: 0` — иначе чарт создаст их с дефолтными значениями.

Чарт создаёт два сервиса, и различать их важно:

| Service | Порт | Для чего |
|---|---|---|
| `loki-gateway` | 80 | nginx-прокси, единая точка входа — её используют promtail и Grafana |
| `loki` | 3100 | сам singleBinary, напрямую обычно не нужен |

### promtail

DaemonSet: по поду на узел, читает `/var/log/pods` и отправляет в Loki.

```yaml
config.clients[0].url: http://loki-gateway.k8s-hw11.svc.cluster.local/loki/api/v1/push
serviceMonitor.enabled: true
```

`serviceMonitor.enabled: true` — promtail сам отдаёт метрики Prometheus, видно, сколько
строк отправлено и не отваливается ли отправка.

> Promtail объявлен deprecated в пользу **Grafana Alloy**: новых фич не будет, Grafana
> рекомендует миграцию. Здесь он поставлен потому, что задание требует именно promtail;
> в новом проекте стоило бы взять Alloy.

### LogQL для демонстрации

```logql
# всё из namespace мониторинга
{namespace="k8s-hw11"}

# логи конкретного приложения
{namespace="k8s-hw11", app="grafana"}

# логи ингресса — тот же трафик, что породил метрики выше
{namespace="ingress-nginx"}

# поиск по подстроке
{namespace="k8s-hw11"} |= "error"

# частота ошибок
sum(rate({namespace="k8s-hw11"} |= "error" [5m]))
```

### grafana

Всё состояние задаётся **provisioning-ом из values**, руками в UI ничего настраивать не
нужно. Поэтому `persistence.enabled: false`: терять нечего, при переустановке всё
приезжает заново. Обратная сторона — provisioned-объекты в UI помечены read-only.

**Datasources** — три, с фиксированными `uid` (на `uid: prometheus` ссылаются правила
алертинга):

| Имя | uid | URL |
|---|---|---|
| Prometheus | `prometheus` | `http://kube-prometheus-stack-prometheus.k8s-hw11.svc.cluster.local:9090` |
| Loki | `loki` | `http://loki-gateway.k8s-hw11.svc.cluster.local` |
| Alertmanager | `alertmanager` | `http://kube-prometheus-stack-alertmanager.k8s-hw11.svc.cluster.local:9093` |

**Дашборды** — два источника:

- по `gnetId` с grafana.com: **1860** Node Exporter Full, **9614** NGINX Ingress
  controller, **13639** Logs / App. Init-контейнер `download-dashboards` скачивает JSON
  при старте пода, поэтому Grafana нужен доступ в интернет на старте;
- через sidecar — все дашборды кластера из `kube-prometheus-stack` (см.
  `forceDeployDashboards` выше).

## SMTP-токен

Grafana отправляет письма через обычный SMTP, и почтовые провайдеры для этого требуют
**пароль приложения** — отдельный токен, а не основной пароль аккаунта (с включённой
двухфакторной аутентификацией основной пароль по SMTP просто не работает).

| Провайдер | Где взять | Хост |
|---|---|---|
| Gmail | [Пароли приложений](https://myaccount.google.com/apppasswords) (нужна включённая 2FA) — [инструкция](https://support.google.com/accounts/answer/185833) | `smtp.gmail.com:587` |
| Яндекс | Профиль → Безопасность → Пароли приложений → «Почта» — [инструкция](https://yandex.ru/support/id/authorization/app-passwords.html) | `smtp.yandex.ru:587` |
| Mail.ru | Настройки → Пароли и безопасность → Пароли для внешних приложений | `smtp.mail.ru:587` |

Полученный токен кладётся в Keychain, а не в репозиторий:

```bash
security add-generic-password -a fastrapier -s smtp-hw11 -w 'полученный-токен' -U
```

## Секреты и env

В git не попадает ни один секрет. `hw-11/.gitignore` исключает `.env`, а пароли скрипты
берут из **macOS Keychain**.

| Переменная | Обязательна | Откуда | По умолчанию |
|---|---|---|---|
| `GRAFANA_ADMIN_PASSWORD` | да | Keychain `grafana-hw11` или `.env` | генерируется скриптом |
| `GRAFANA_SMTP_ENABLED` | нет | `.env` или окружение | `false` |
| `GRAFANA_SMTP_PASSWORD` | при SMTP=true | Keychain `smtp-hw11` или `.env` | — |
| `GRAFANA_SMTP_USER` | при SMTP=true | `.env` | — |
| `GRAFANA_SMTP_HOST` | нет | `.env` | `smtp.gmail.com:587` |
| `GRAFANA_SMTP_FROM_ADDRESS` | нет | `.env` | `= GRAFANA_SMTP_USER` |
| `ALERT_EMAIL` | нет | `.env` | `= GRAFANA_SMTP_USER` |

```bash
# пароли — в Keychain
security add-generic-password -a fastrapier -s grafana-hw11 -w 'пароль-админа' -U
security add-generic-password -a fastrapier -s smtp-hw11    -w 'smtp-токен'    -U

# несекретное — в .env
cp hw-11/.env.example hw-11/.env
```

`scripts/common.sh` → `load_env()` подхватывает `.env`, добирает пароли из Keychain и
падает с подсказкой, если чего-то не хватает. В values Grafana пароли читаются через
`requiredEnv` — установка с пустым паролем невозможна по построению.

Внутри кластера SMTP-токен лежит в **Secret**, а не в ConfigMap: значение уезжает в
`envRenderSecret.GF_SMTP_PASSWORD`, а `grafana.ini` ссылается на него через
`password = $__env{GF_SMTP_PASSWORD}`. Иначе токен оказался бы в открытом виде в
ConfigMap `grafana` рядом с остальным конфигом.

## Алертинг

При `GRAFANA_SMTP_ENABLED=true` контакт, политика маршрутизации и правила описаны в секции `alerting:` values Grafana и
приезжают файлами в `/etc/grafana/provisioning/alerting/`.

**Contact point** `email-hw11` — тип `email`, адрес из `$ALERT_EMAIL`, `singleEmail: true`
(одно письмо на группу алертов, а не по письму на каждый).

**Notification policy** — дефолтная политика целиком уходит на `email-hw11`:
`group_by: [grafana_folder, alertname]`, `group_wait: 30s`, `group_interval: 1m`,
`repeat_interval: 1h`.

**Alert rules** — два, оба по метрикам ингресса:

| uid | Условие | `for` | Зачем |
|---|---|---|---|
| `hw11-ingress-rps` | `sum(rate(nginx_ingress_controller_requests[1m])) > 1` | 1m | Демонстрационное: срабатывает от curl-цикла, письмо приходит за пару минут |
| `hw11-ingress-5xx` | доля 5xx `> 0.05` | 2m | Осмысленное: деградация сервиса |

Правило Grafana — это не одна строка PromQL, а граф из запроса (`refId: A`,
`datasourceUid: prometheus`) и выражения-порога (`refId: C`,
`datasourceUid: __expr__`, `type: threshold`); `condition: C` указывает, какой узел
считать результатом. Оба правила используют `noDataState: OK`: при нулевом трафике
метрики нет, и это норма, а не инцидент.

В знаменателе правила 5xx стоит `clamp_min(..., 0.001)`: без него при нулевом трафике
получается `0/0 = NaN`, и правило уходит в `NoData` вместо `OK`.

### Как проверить, что письма ходят

`./scripts/05-test-alert.sh` делает обе проверки по очереди.

**1. Синтетическое тестовое письмо** — то же, что кнопка **Test** у контакта в UI. Скрипт
берёт uid и настройки контакта из `GET /api/v1/provisioning/contact-points` и отправляет:

```
POST /api/alertmanager/grafana/config/api/v1/receivers/test
{
  "alert":     { "labels": {...}, "annotations": {...} },
  "receivers": [ { "name": "email-hw11",
                   "grafana_managed_receiver_configs": [ { "uid": "email-hw11", ... } ] } ]
}
```

`uid` существующей интеграции обязателен: по нему Grafana достаёт сохранённые secure
settings, для неизвестного uid отвечает `400`.

> Этот эндпоинт есть в **Grafana 12.x** — чарт `grafana` 10.5.15 ставит appVersion
> **12.3.1**, так что всё работает. В **Grafana 13** его удалили: он отвечает `410 Gone`,
> а замена живёт в новом API
> `/apis/notifications.alerting.grafana.app/v1beta1/namespaces/default/receivers/{uid}/test`
> (uid там — `base64url` от имени контакта, для `email-hw11` это `ZW1haWwtaHcxMQ`).
> Скрипт распознаёт `410` и подсказывает воспользоваться кнопкой в UI.

**2. Настоящее срабатывание правила** — скрипт ~150 секунд гоняет запросы через ингресс,
чтобы `hw11-ingress-rps` перешло в `firing`, и опрашивает его состояние. Это проверка всей
цепочки целиком: метрика → правило → политика → контакт → SMTP → письмо. Тестовая кнопка
такого не покажет — она отправляет письмо напрямую, минуя правила и политику.

Кнопка в UI, если нужна вручную:
`http://grafana-hw11.local/alerting/notifications` → `email-hw11` → Edit → Test.

Если письма нет — смотреть в «Спам» и в логи Grafana:

```bash
kubectl logs deployment/grafana -n k8s-hw11 -c grafana | grep -i smtp
```

## Полезные команды

```bash
# что в кластере
kubectl get pods -n k8s-hw11
kubectl get svc,ingress -n k8s-hw11
kubectl get servicemonitor -n k8s-hw11
kubectl get prometheusrule -n k8s-hw11

# метрики ингресса напрямую с контроллера, минуя Prometheus
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- \
  curl -s localhost:10254/metrics | grep nginx_ingress_controller_requests | head

# состояние таргетов Prometheus
curl -s http://prometheus-hw11.local/api/v1/targets | python3 -m json.tool | head -40

# запрос метрики через API
curl -s --get http://prometheus-hw11.local/api/v1/query \
  --data-urlencode 'query=sum(rate(nginx_ingress_controller_requests[1m]))'

# логи Loki через port-forward
kubectl port-forward -n k8s-hw11 svc/loki-gateway 13100:80
curl -s http://127.0.0.1:13100/loki/api/v1/labels

# нагрузить ингресс, чтобы сработало правило
while true; do curl -s -o /dev/null http://prometheus-hw11.local/-/ready; done

# helmfile
cd hw-11 && helmfile list && helmfile diff
```

## Чеклист для защиты

Пошаговый план демонстрации: **[CHECKLIST.MD](CHECKLIST.MD)**

## Очистка

```bash
cd hw-11
./teardown.sh                  # релизы, PVC, /etc/hosts; CRD остаются
./teardown.sh --crds           # плюс CRD Prometheus Operator (общие на кластер!)
kubectl delete namespace k8s-hw11
minikube addons disable ingress
```

CRD Prometheus Operator по умолчанию не удаляются: они общие на весь кластер, и снос
затронул бы мониторинг в других namespace. `helm uninstall` их тоже не трогает — это
поведение helm для CRD, а не недоработка чарта.
