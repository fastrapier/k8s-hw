# ДЗ 7 — Работа с масштабированием

Go HTTP API с PostgreSQL под нагрузкой Locust: начальные `requests`/`limits`,
поиск критической точки, горизонтальное (HPA) и вертикальное (VPA)
масштабирование, деплой самого Locust через оператор.

## Архитектура

```
                       ┌─────────────────────────────────────────────────────────────┐
   локально:           │      Kubernetes (Minikube, namespace: k8s-hw7)              │
   scripts/05,06,07    │                                                             │
   locust --headless   │  ┌───────────────────┐                                       │
        │              │  │ metrics-server    │ (addon minikube, ns kube-system)      │
        │              │  │ metrics.k8s.io    │                                       │
        │              │  └────┬─────────┬────┘                                       │
        │              │       │ CPU/RAM │ CPU/RAM                                    │
        │              │       ▼         ▼                                            │
        │              │  ┌─────────┐  ┌──────────────────┐                           │
        │              │  │   HPA   │  │  VPA recommender │  updateMode: "Recreate"   │
        │              │  │ api     │  │  api             │  → memory request         │
        │              │  │ cpu 70% │  └──────────────────┘                           │
        │              │  │ 2..6    │                                                 │
        │              │  └────┬────┘                                                 │
        │              │       │ scale                                                │
        ▼              │       ▼                                                      │
  ┌───────────┐        │  ┌──────────────────────────────────┐    ┌────────────────┐  │
  │ Ingress   │───────►│  │ Deployment api (2..6 реплик)     │───►│ StatefulSet    │  │
  │api-hw7.   │        │  │  GET /db/requests                │    │ postgres       │  │
  │local      │        │  │  GET /db/report   (SELECT+SHA256)│    │  requests      │  │
  └───────────┘        │  │  GET /db/stats                   │    │  cron_runs     │  │
        ▲              │  │  GET /healthz, /readyz           │    └────────────────┘  │
        │              │  │  requests cpu 50m  / mem 64Mi    │            ▲           │
        │              │  │  limits   cpu 250m / mem 128Mi   │            │           │
   в кластере:         │  └──────────────────────────────────┘     Job миграций       │
   часть 4             │             ▲                             CronJob api-cron   │
                       │             │ HTTP                                           │
  ┌───────────┐        │  ┌──────────┴───────────────────────┐                         │
  │ Ingress   │───────►│  │ load-test-v2-master (web UI 8089)│                         │
  │locust-hw7.│        │  │ load-test-v2-worker  x2          │                         │
  │local      │        │  └──────────────────────────────────┘                         │
  └───────────┘        │             ▲                                                 │
        Service        │             │ создаёт Job-ы по CR                             │
  load-test-v2-webui   │  ┌──────────┴───────────┐   ┌──────────────────────────────┐  │
  :8089 (наш)          │  │ locust-operator      │◄──│ LocustTest load-test-v2      │  │
                       │  │ (locust.io/v2 CRD)   │   │ + ConfigMap с locustfile.py  │  │
                       │  └──────────────────────┘   └──────────────────────────────┘  │
                       └─────────────────────────────────────────────────────────────┘
```

## Структура проекта

```
hw-7/
├── init.sh                        # Точка входа: 01 → 02 → 03 → 08
├── teardown.sh                    # Полная очистка
├── TASK.MD                        # Задание
├── CHECKLIST.MD                   # Порядок демонстрации на защите
│
├── scripts/
│   ├── common.sh                  # Общие функции и константы
│   ├── 01-metrics-server.sh       # часть 1: addon metrics-server + ожидание метрик
│   ├── 02-install-vpa.sh          # часть 3: контроллеры VPA (ставятся ДО деплоя — см. ниже)
│   ├── 03-build-and-deploy.sh     # части 1+3: werf converge (API, Postgres, HPA, VPA)
│   ├── 04-measure.sh              # части 1+2: kubectl top N раз, min/avg/max по подам
│   ├── 05-locust-local.sh         # часть 2: одиночный прогон по locust.conf
│   ├── 06-find-max-users.sh       # часть 2: ступенчатый поиск максимума пользователей
│   ├── 07-hpa-demo.sh             # часть 3: нагрузка + лог реакции HPA + describe vpa
│   ├── 08-locust-operator.sh      # часть 4: оператор + чарт с LocustTest
│   ├── parse-stats.sh             # разбор строки Aggregated из locust *_stats.csv
│   └── migrations-entrypoint.sh   # entrypoint образа миграций (golang-migrate)
│
├── main.go                        # HTTP-сервер
├── cmd/cronjob/main.go            # CronJob: запись в cron_runs
├── internal/
│   ├── api/                       # роутер + swagger-описания ответов
│   ├── config/                    # конфигурация из env (префикс APP_)
│   ├── db/                        # pgx-пул, SELECT/INSERT
│   └── handler/                   # хендлеры, в т.ч. GET /db/* под нагрузку
├── migrations/                    # 0001 requests, 0002 cron_runs, 0003 seed 5000 строк
├── docs/                          # swagger.json (go:embed) + /swagger UI
├── docker/                        # app / migrations / cron Dockerfile
├── werf.yaml                      # образы app, migrations, cron
│
├── .helm/                         # чарт приложения (werf)
│   ├── Chart.yaml
│   ├── values.yaml                # global.postgres.*
│   └── charts/
│       ├── backend/               # API: Deployment, Service, Ingress, HPA, VPA,
│       │   │                      #      ConfigMap+Secret, Job миграций, CronJob
│       │   ├── values.yaml         #      ← здесь requests/limits, HPA и VPA
│       │   └── templates/
│       └── postgres/              # StatefulSet, Service, Secret, ConfigMap
│
├── locust/
│   ├── locust.conf                # настройки части 2: host, users, spawn-rate, run-time
│   └── results/                   # CSV и логи прогонов (в .gitignore)
│
└── helm/locust/                   # чарт части 4
    ├── values.yaml
    ├── files/locustfile.py        # ЕДИНСТВЕННЫЙ источник правды для теста
    └── templates/
        ├── configmap.yaml         # ConfigMap из files/locustfile.py
        ├── locusttest.yaml        # LocustTest load-test-v2
        ├── webui-service.yaml     # Service load-test-v2-webui:8089
        └── webui-ingress.yaml     # Ingress locust-hw7.local → load-test-v2-webui
```

## Приложение

Go API с PostgreSQL, взятый из ДЗ 1-2 (модуль `hw-7`, go 1.26). Нагружать нужно
что-то с реальной работой, поэтому добавлены GET-эндпоинты над БД:

| Эндпоинт | Что делает | Вес в тесте |
|---|---|---|
| `GET /db/requests?limit=N` | `SELECT id, created_at ... LIMIT N` (по умолчанию 25, максимум 200) | 5 |
| `GET /db/report?rows=N` | тот же SELECT + `APP_REPORT_ROUNDS` раундов SHA-256 | 3 |
| `GET /db/stats` | агрегаты `count/min/max/count FILTER` | 2 |
| `GET /healthz` | без БД, дешёвый — фон для замера деградации | 1 |
| `POST /db/requests` | вставка строки (в нагрузочном тесте не используется) | — |
| `GET /readyz` | прогрев + `Ping` БД — readiness probe | — |
| `GET /swagger` | Swagger UI | — |

Два решения, которые стоит пояснить:

- **Зачем хеширование в `/db/report`.** HPA в этом ДЗ масштабирует API по CPU.
  Чистые SELECT-ы грузят Postgres, а под API большую часть времени ждёт ответа
  и по CPU почти не растёт — HPA не сработал бы. Хеш-цикл переносит нагрузку на
  CPU того пода, который HPA и масштабирует. Тяжесть регулируется значением
  `backend.env.APP_REPORT_ROUNDS`.
- **Миграция `0003_seed_requests`** наливает 5000 строк: на пустой таблице
  `SELECT ... LIMIT 25` отвечает мгновенно и ничего не показывает.

Каждый ответ содержит `pod` и заголовок `X-Pod-Name` — по ним видно, что после
масштабирования трафик реально расходится по новым подам.

**Vault здесь не используется** сознательно: тема ДЗ — масштабирование, а не
секреты. Реквизиты Postgres лежат в обычном `Secret`, собранном из
`.helm/values.yaml`. Схема с Vault + AppRole показана в ДЗ 1-2 и ДЗ 3-4.

Локальная проверка кода:

```bash
cd hw-7
go build ./... && go vet ./... && go test ./...
```

Swagger-спека вшита в бинарник через `go:embed` и обновляется локально
(в образе генератора нет):

```bash
swagger generate spec -o docs/swagger.json --scan-models
```

## Быстрый старт

```bash
minikube start
minikube addons enable ingress
minikube tunnel            # отдельный терминал, нужен для *.local
cd hw-7 && ./init.sh
```

`init.sh` разворачивает инфраструктуру (metrics-server, VPA, приложение,
locust-operator). Нагрузочные скрипты интерактивные и идут минутами, поэтому
запускаются отдельно — порядок в [CHECKLIST.MD](CHECKLIST.MD).

| Адрес | Что |
|---|---|
| http://api-hw7.local/healthz | API |
| http://api-hw7.local/swagger | Swagger UI |
| http://locust-hw7.local | Locust web UI (часть 4) |

### Почему 02 (VPA) идёт до 03 (деплой)

Чарт приложения содержит объект `VerticalPodAutoscaler`. CRD
`verticalpodautoscalers.autoscaling.k8s.io` приносит чарт VPA, поэтому без
него `werf converge` упал бы на неизвестном `kind`. Если VPA не нужен:

```bash
werf converge --dev --repo ghcr.io/fastrapier/hw7 --namespace k8s-hw7 \
  --set backend.vpa.enabled=false
```

## Часть 1. Метрики и начальные лимиты

`scripts/01-metrics-server.sh` включает addon и ждёт, пока
`kubectl top nodes` начнёт отвечать (до этого HPA показывает `<unknown>`,
а VPA не считает рекомендации).

`scripts/04-measure.sh` снимает `kubectl top pods` несколько раз и печатает
min/avg/max CPU и RAM по каждому поду:

```bash
SAMPLES=12 INTERVAL=5 ./scripts/04-measure.sh                    # покой
SAMPLES=40 INTERVAL=5 ./scripts/04-measure.sh                    # во время нагрузки
SELECTOR=app.kubernetes.io/name=postgres ./scripts/04-measure.sh # Postgres
```

Начальные значения (`.helm/charts/backend/values.yaml`):

```yaml
resources:
  requests: { cpu: 50m,  memory: 64Mi }
  limits:   { cpu: 250m, memory: 128Mi }
```

Логика: `requests` — чуть выше наблюдаемого покоя, чтобы планировщик не
недооценивал под; `limits` — примерно 5x, чтобы всплеск не упирался в throttling
раньше, чем HPA успеет добавить реплику.

## Часть 2. Стресс-тесты на Locust

```bash
brew install locust        # проверено на locust 2.46.4
```

Тест — `helm/locust/files/locustfile.py`. Файл лежит в каталоге чарта, потому
что Helm `.Files.Get` не читает за пределами чарта, а ConfigMap части 4 должен
собираться из него же. Локальные скрипты ссылаются на этот же файл — копий и
симлинков нет.

Настройки прогона — `locust/locust.conf` (URL приложения, максимум
пользователей, прирост в секунду, длительность):

```ini
host        = http://api-hw7.local
users       = 100
spawn-rate  = 10
run-time    = 3m
headless    = true
```

Локальные скрипты передают Locust адрес `http://127.0.0.1` и заголовок
`Host: api-hw7.local`: запрос всё равно проходит через `minikube tunnel` и
Ingress, но macOS не тратит около 5 секунд на разрешение имени `.local`.
Значение `host` в конфиге остаётся адресом Ingress; для кластерного Locust
оператор задаёт внутренний адрес Service.

Одиночный прогон:

```bash
./scripts/05-locust-local.sh
USERS=200 SPAWN_RATE=20 RUN_TIME=5m ./scripts/05-locust-local.sh
LOCUST_TARGET=http://127.0.0.1:8080 ./scripts/05-locust-local.sh
```

Поиск максимума — `scripts/06-find-max-users.sh`. Гоняет ступени, после каждой
читает `Aggregated` из `*_stats.csv` и останавливается на первой ступени,
где появились ошибки или `avg` превысил порог из задания:

```bash
STEPS="10 25 50 100 200 400" STEP_RUN_TIME=1m MAX_AVG_MS=5000 ./scripts/06-find-max-users.sh
```

> **Нагрузку подаём через Ingress, а не `kubectl port-forward`.**
> `port-forward` прибивает трафик к одному поду — Deployment масштабируется,
> а грузится одна реплика, и демонстрация HPA теряет смысл. Ingress
> раскидывает запросы по всем эндпоинтам Service.

### Результаты исследования

> **Заполняется после прогона на живом кластере.** Цифры зависят от машины
> (сколько CPU отдано minikube), поэтому в репозиторий вписываются фактические.

| Состояние | Users | RPS | avg, ms | p95, ms | Ошибки | Реплик API | CPU/под | RAM/под |
|---|---|---|---|---|---|---|---|---|
| Покой | 0 | 0 | — | — | 0 | 2 | 1m | 26–27Mi |
| Проверенная нагрузка | 1200 | 532 | 2,8 | 2 | 0 | 2 → 4 | до 56m | до 31Mi |
| **Критическая точка** | `___` | `___` | `___` | `___` | 0 | `___` | `___m` | `___Mi` |
| Перегрузка (первая упавшая ступень) | `___` | `___` | `___` | `___` | `___` | `___` | `___m` | `___Mi` |

Проверенные прогоны 06.10.2026 внутри кластера: при 1200 пользователях за
2 минуты первый дал 63 974 запроса, 0 ошибок, 533 RPS, p95 2 мс и рост HPA
с 2 до 3 реплик с последующим возвратом к 2. Повторный прогон дал 63 820
запросов, 0 ошибок, 532 RPS, avg 2,8 мс, p95 2 мс и рост HPA с 2 до 4.
После снятия нагрузки HPA последовательно снизил число реплик до 3 и 2.
Во время повтора `04-measure.sh` снял 20 проб с интервалом 5 с: пики двух
исходных pod'ов — 53m/31Mi и 56m/31Mi; среднее по пробам — 25m/29Mi на pod.
Новые pod'ы не попали в серию проб. Это успешная ступень,
а не найденный максимум. Локальный прогон на 1200 через `minikube tunnel` дал ошибки
`Connection refused` после остановки локального слушателя порта 80; его
результат не характеризует предел API.

Текущие `requests`/`limits` API — CPU `50m/250m`, RAM `64Mi/128Mi`.
На проверенной ступени пик CPU был `56m`, RAM `31Mi`; запас лимитов есть.
HPA использует CPU request `50m` как знаменатель и во втором прогоне
масштабировал при `54m` (`109%` от request) против цели `70%`.
Менять ресурсы по этой ступени рано: первая ступень с ошибками приложения
внутри кластера ещё не найдена.

Перед новым стресс-тестом после перезапуска кластера проверьте схему БД:

```bash
kubectl exec -n k8s-hw7 postgres-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -Atc "SELECT count(*) FROM requests"'
```

Если таблицы нет, повторите `./scripts/03-build-and-deploy.sh`: Helm hook
запустит Job миграций. Прогон 07.10.2026 на 1600 пользователей не является
проверкой предела: `/healthz` отвечал, но все DB-эндпоинты возвращали 500,
поскольку в Postgres отсутствовала таблица `requests` ещё до нагрузки.

Где брать цифры:

- Users / RPS / avg / p95 / ошибки — вывод `06-find-max-users.sh` или
  `parse-stats.sh locust/results/<прогон>_stats.csv`;
- CPU/RAM на под — `04-measure.sh`, запущенный параллельно с прогоном;
- реплики — `kubectl get hpa api -n k8s-hw7`.

**Новые limits после стресс-теста.** Правило: `requests` ≈ потребление в
критической точке, `limits` — с запасом 1.5–2x поверх наблюдаемого максимума.
Значения меняются в `.helm/charts/backend/values.yaml` и применяются
`./scripts/03-build-and-deploy.sh`:

```yaml
resources:
  requests: { cpu: ___m, memory: ___Mi }   # ← из строки «Критическая точка»
  limits:   { cpu: ___m, memory: ___Mi }
```

Отдельно стоит сверить их с рекомендациями VPA (`kubectl describe vpa api`) —
это независимая проверка ручного замера.

## Часть 3. HPA и VPA

### HPA

`.helm/charts/backend/templates/hpa.yaml`, `autoscaling/v2`:

```yaml
minReplicas: 2
maxReplicas: 6
metrics:
  - resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
behavior:
  scaleUp:   { stabilizationWindowSeconds: 0,   selectPolicy: Max,
               policies: [ {type: Percent, value: 100, periodSeconds: 15},
                           {type: Pods,    value: 2,   periodSeconds: 15} ] }
  scaleDown: { stabilizationWindowSeconds: 300, selectPolicy: Min,
               policies: [ {type: Pods, value: 1, periodSeconds: 60} ] }
```

Best practices, применённые здесь:

| Практика | Как сделано и почему |
|---|---|
| `requests` обязательны | `averageUtilization` — это доля от `requests`. Без них HPA не может посчитать метрику и показывает `<unknown>`. |
| Метки Job и CronJob отделены от API | HPA выбирает pod'ы по селектору Deployment. Pod миграций без CPU `requests` в этой выборке оставлял метрику `<unknown>`, поэтому у Job и CronJob свои `app.kubernetes.io/name`. |
| `minReplicas` ≥ 2 | Одна реплика — точка отказа: любой rollout или eviction обнуляет сервис. |
| Целевая утилизация 70%, не 90% | Между «метрика выросла» и «под принял трафик» проходят десятки секунд. 30% запаса — время на масштабирование. |
| Масштабирование только по CPU | Go-процесс не отдаёт RSS ядру сразу после пика. Метрика по памяти удержала бы реплики поднятыми навсегда: память не падает — HPA не сжимается. |
| Быстро вверх, медленно вниз | Вверх — окно 0 и до +100%/+2 подов за 15 с. Вниз — окно 300 с и по одному поду в минуту, иначе HPA «пилит» реплики на всплесках трафика. |
| `replicas` не в шаблоне | Когда `autoscaling.enabled=true`, поле `replicas` в Deployment не рендерится, иначе каждый `helm upgrade` сбрасывал бы масштаб к значению из values. |
| Readiness probe | Новый под получает трафик только после `/readyz`, иначе масштабирование добавляет 502-е. |

Проверенная демонстрация из каталога `hw-7` (Locust operator уже установлен):

```bash
kubectl delete locusttest load-test-v2 -n k8s-hw7
helm upgrade --install locust ./helm/locust -n k8s-hw7 \
  --set load.users=1200 --set load.spawnRate=40 --set load.runTime=2m
# В другом терминале:
kubectl get hpa api -n k8s-hw7 -w
kubectl logs -n k8s-hw7 job/load-test-v2-master -f
```

После прогона `kubectl describe hpa api -n k8s-hw7` показывает события
`SuccessfulRescale`. В проверенных прогонах число реплик выросло с 2 до 3
и с 2 до 4, затем HPA вернул число реплик к 2. Точное число
реплик зависит от нагрузки и доступных ресурсов кластера.

`scripts/07-hpa-demo.sh` остаётся вариантом локального прогона с логом
наблюдения; при большой нагрузке локальный `minikube tunnel` может оборваться.

### VPA

Контроллеры — чарт `fairwinds-stable/vpa` версии 5.0.1 (VPA 1.7.1),
recommender + updater + admission controller. Сертификаты для вебхука чарт
делает сам (`kube-webhook-certgen` в pre-install хуке), cert-manager не нужен.
metrics-server подчартом отключён — он уже стоит addon-ом minikube.

Объект — `.helm/charts/backend/templates/vpa.yaml`, `autoscaling.k8s.io/v1`:

```yaml
updatePolicy:
  updateMode: "Recreate"
resourcePolicy:
  containerPolicies:
    - containerName: api
      controlledResources: ["memory"]
      controlledValues: RequestsOnly
      minAllowed: { memory: 32Mi }
      maxAllowed: { memory: 512Mi }
```

Best practices:

| Практика | Как сделано и почему |
|---|---|
| `updateMode: "Recreate"`, только память | HPA масштабирует по CPU, VPA меняет memory request. CPU request остаётся `50m`, поэтому знаменатель метрики HPA не меняется. Для применения новой рекомендации VPA может пересоздать pod. |
| `controlledValues: RequestsOnly` | `RequestsAndLimits` пересчитал бы и `limits`, сохраняя пропорцию, и съел бы запас на всплеск, заложенный в части 1. |
| `min/maxAllowed` заданы | Ограничивают рекомендацию снизу (не «0m», на котором под не стартует) и сверху (не больше, чем есть на узле minikube). |
| Режим указан строкой | `Recreate` явно задаёт применение рекомендаций, не полагаясь на значение по умолчанию. |
| Один VPA на один контроллер | Пересечение `targetRef` у двух VPA — неопределённое поведение. |

Проверка рекомендаций:

```bash
kubectl describe vpa api -n k8s-hw7
```

В `Recommendation → Container Recommendations` должны быть `Target`,
`Lower Bound`, `Upper Bound`, `Uncapped Target` по памяти.
После включения VPA новые pod'ы API получили CPU request `50m` и memory
request `49566436` байт (~47Mi); аннотация `vpaUpdates` указывает только
`memory request`. В шаблоне Deployment осталось `50m/64Mi`, поскольку
VPA меняет ресурсы создаваемого pod'а, а не шаблон Deployment.
Рекомендации появляются не сразу — recommender набирает историю: ориентир
5–15 минут работы, лучше под нагрузкой. Пока их нет, `describe` показывает
только `spec`, а `Provided` в condition-ах равен `False`.

## Часть 4. Деплой Locust

`scripts/08-locust-operator.sh` ставит чарт
`locust-k8s-operator/locust-k8s-operator` версии 2.3.1 (repo
`https://abdelrhmanhamouda.github.io/locust-k8s-operator/`) и разворачивает
`helm/locust`.

Чарт `helm/locust` создаёт:

| Ресурс | Имя | Комментарий |
|---|---|---|
| ConfigMap | `load-test-v2-locustfile` | из `files/locustfile.py`, ключ `locustfile.py` |
| LocustTest | `load-test-v2` | `locust.io/v2`, параметры как в части 2 |
| Service | `load-test-v2-webui` | порт 8089, наш собственный — см. ниже |
| Ingress | `load-test-v2-webui` | `locust-hw7.local` → `load-test-v2-webui:8089` |

По `LocustTest` оператор сам создаёт Job-ы `load-test-v2-master` и
`load-test-v2-worker` и Service `load-test-v2-master`.

**Грабли: Service `load-test-v2-webui` оператор не создаёт.** Он делает только
`<имя>-master` с портами 5557/5558 (обмен master↔worker) и намеренно
исключает 8089 — в его коде есть отдельная ветка `if port == WebUIPort { continue }`,
а документация предлагает ходить в UI через `kubectl port-forward`. Так было и
в старом Java-операторе. Задание же требует Ingress именно на
`load-test-v2-webui:8089`, поэтому Service объявлен в нашем чарте с тем же
селектором, которым оператор помечает под мастера:

```yaml
selector:
  performance-test-pod-name: load-test-v2-master
```

Ещё два момента про CRD:

- **Команда — это `args`, а не `command`.** Оператор передаёт строку из
  `master.command` как аргументы к ENTRYPOINT образа, поэтому она не должна
  начинаться со слова `locust`.
- **Часть флагов оператор добавляет сам**: `--master`, `--worker`,
  `--master-host`, `--master-port`, `--expect-workers`, `--autostart`,
  `--autoquit`. Дублировать их в `command` нельзя. `--autostart` означает, что
  тест стартует без нажатия кнопки, а web UI остаётся живым и показывает прогон.
  `master.autoquit.timeout: 600` держит мастера 10 минут после окончания
  прогона — иначе UI и Ingress отдавали бы 503 сразу после теста.

Повторный прогон (Job-ы иммутабельны, поэтому CR пересоздаётся):

```bash
kubectl delete locusttest load-test-v2 -n k8s-hw7
helm upgrade --install locust ./helm/locust -n k8s-hw7
```

## Полезные команды

```bash
# Метрики
kubectl top nodes
kubectl top pods -n k8s-hw7
kubectl top pods -n k8s-hw7 -l app.kubernetes.io/name=api

# Масштабирование
kubectl get hpa api -n k8s-hw7
kubectl get hpa api -n k8s-hw7 -w
kubectl describe hpa api -n k8s-hw7
kubectl describe vpa api -n k8s-hw7
kubectl get pods -n k8s-hw7 -l app.kubernetes.io/name=api -w

# Приложение
curl http://api-hw7.local/healthz
curl -i http://api-hw7.local/db/requests?limit=5     # смотреть X-Pod-Name
curl http://api-hw7.local/db/stats
curl "http://api-hw7.local/db/report?rows=100"
kubectl logs -n k8s-hw7 deployment/api --tail=20

# Postgres
kubectl exec -n k8s-hw7 postgres-0 -- psql -U hw7 -d hw7 -c 'SELECT count(*) FROM requests;'

# Locust в кластере
kubectl get locusttest -n k8s-hw7
kubectl logs -n k8s-hw7 job/load-test-v2-master -f
kubectl get svc,ingress -n k8s-hw7 -l app.kubernetes.io/name=locust

# Статическая проверка без кластера
go build ./... && go vet ./... && go test ./...
werf render --dev --stub-tags --repo ghcr.io/fastrapier/hw7 --namespace k8s-hw7
helm lint helm/locust && helm template load-test helm/locust -n k8s-hw7
```

## Чеклист для защиты

Пошаговый план демонстрации: **[CHECKLIST.MD](CHECKLIST.MD)**

## Очистка

```bash
./teardown.sh
kubectl delete namespace k8s-hw7
minikube addons disable metrics-server   # если больше не нужен
```
