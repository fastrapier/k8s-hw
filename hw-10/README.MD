# ДЗ 10 — Работа с безопасностью

Три инструмента на трёх разных рубежах: секреты ловятся до коммита и в истории,
уязвимости зависимостей — в пайплайне, качество кода — в SonarQube.

## Архитектура

```
РАЗРАБОТЧИК (локально)
┌──────────────────────────────────────────────────┐
│  git commit                                      │
│      │                                           │
│      ▼                                           │
│  ┌────────────────────────────────────────────┐  │
│  │ pre-commit — .pre-commit-config.yaml       │  │
│  │                                            │  │
│  │  trailing-whitespace   ┐ только файлы      │  │
│  │  end-of-file-fixer     ┘ этого ДЗ          │  │
│  │  check-merge-conflict  ┐                   │  │
│  │  check-yaml            │ весь репозиторий  │  │
│  │  detect-private-key    │                   │  │
│  │  TruffleHog            ┘ --since-commit    │  │
│  │                          HEAD              │  │
│  └────────────────────────────────────────────┘  │
│      │ секрет найден → коммит не создан           │
│      ▼                                           │
│  git push ───────────────────────────────────────┼───┐
│                                                  │   │
│  Локальные прогоны тех же проверок:              │   │
│   scripts/04-sonar-scan-local.sh                 │   │
│   scripts/05-trivy-local.sh                      │   │
│   scripts/06-trufflehog-local.sh                 │   │
└──────────────────────────────────────────────────┘   │
                                                       │
GitHub Actions — .github/workflows/hw10-security.yml   │
on: pull_request │ push main │ dispatch │ schedule ◄───┘
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │ job: trufflehog │  │ job: trivy       │  │ job: sonarqube  │  │
│  ├─────────────────┤  ├──────────────────┤  ├─────────────────┤  │
│  │ PR   → дифф     │  │ fs: vuln +       │  │ runs-on:        │  │
│  │       base..head│  │     secret +     │  │  vars.HW8_RUNNER│  │
│  │ push → вся      │  │     misconfig    │  │  или ubuntu     │  │
│  │        история  │  │                  │  │                 │  │
│  │                 │  │ гейт: CRITICAL   │  │ нет секретов →  │  │
│  │ --results=      │  │  + есть фикс     │  │  ::warning:: и  │  │
│  │  verified,      │  │                  │  │  пропуск        │  │
│  │  unknown        │  │ образ hw8:latest │  │                 │  │
│  └─────────────────┘  └────────┬─────────┘  └────────┬────────┘  │
│                          SARIF │                     │           │
│                                ▼                     │           │
│                     ┌────────────────────┐           │           │
│                     │ Security tab       │           │           │
│                     │ (Code scanning)    │           │           │
│                     └────────────────────┘           │           │
└──────────────────────────────────────────────────────┼───────────┘
                                                       │
   self-hosted раннер ДЗ 8 (ARC внутри minikube) —     │
   только он видит SonarQube по внутреннему адресу     │
                                                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  Kubernetes (Minikube, namespace: k8s-hw10)                      │
│                                                                  │
│   Ingress sonarqube-hw10.local                                   │
│        │                                                         │
│        ▼                                                         │
│   Service sonarqube-sonarqube:9000                               │
│        │                                                         │
│        ▼                                                         │
│   StatefulSet sonarqube-sonarqube                                │
│     image: sonarqube:<ver>-community (Community Build)           │
│     встроенная H2 + Elasticsearch, PVC 5Gi                       │
└──────────────────────────────────────────────────────────────────┘
```

## Структура проекта

Часть файлов **обязана** лежать в корне репозитория — не по стилю, а потому что
инструменты ищут их только там:

```
.github/workflows/
└── hw10-security.yml        # GitHub читает workflow только из .github/workflows/

.pre-commit-config.yaml      # pre-commit ищет конфиг в корне git-репозитория
                             #   и работает с индексом целиком
sonar-project.properties     # sonar-scanner читает его из sonar.projectBaseDir,
                             #   а анализируется весь репозиторий (один проект)
.trivyignore.yaml            # реестр принятых рисков; Trivy берёт ignore-файл
                             #   относительно директории сканирования (корень)

hw-10/
├── init.sh                  # 01 → 02 → 03
├── teardown.sh              # Полная очистка
├── TASK.MD                  # Задание
├── CHECKLIST.MD             # Чеклист для защиты
│
├── scripts/
│   ├── common.sh                  # Общие функции + Keychain + ожидание SonarQube
│   ├── 01-precommit.sh            # brew install + pre-commit install + прогон
│   ├── 02-deploy-sonarqube.sh     # helm upgrade --install SonarQube
│   ├── 03-configure-sonarqube.sh  # пароль, проект, токен [--set-secrets]
│   ├── 04-sonar-scan-local.sh     # sonar-scanner локально (без CI)
│   ├── 05-trivy-local.sh          # Trivy локально: отчёт + гейт
│   └── 06-trufflehog-local.sh     # TruffleHog локально [--all]
│
└── helm/
    └── sonarqube-values.yaml      # values чарта под minikube (без секретов)
```

## TruffleHog — секреты

### Почему два рубежа

| Рубеж | Что сканирует | Зачем |
|---|---|---|
| pre-commit | дифф относительно `HEAD` | секрет не попадает в историю вообще |
| CI, pull request | диапазон `base..head` | быстро; ловит то, что закоммитили в обход хука |
| CI, push/schedule | вся история ветки | ловит секрет, добавленный и удалённый внутри PR — в диффе его уже нет, в истории есть |

Хук — `repo: local` + `language: system`, как рекомендует README самого проекта:
TruffleHog ставится через brew, а не собирается pre-commit-ом.

В workflow действие подключено как `trufflesecurity/trufflehog@main`. Это не
небрежность: у проекта **нет движущегося тега `v3`** (только точные `v3.x.y`),
и `@main` стоит во всех примерах официального README. Диапазон задаётся так:

```yaml
base: ''
head: ${{ github.event_name == 'pull_request' && '' || github.ref_name }}
```

При пустых `base`/`head` действие само достаёт `base..head` из события
pull_request. На push/schedule пустой `base` вместе с `head=<ветка>` — это
документированный рецепт «просканировать всю ветку».

### Про `--results=verified,unknown` и dev-пароли в репозитории

В прошлых ДЗ в открытом виде лежат заглушки: `redis_secret_pass`,
root-токен Vault `root`, `rabbitmq_password`. Пайплайн от них не краснеет, и
исключения для них не понадобились — по двум причинам.

1. TruffleHog ищет **учётные данные известных провайдеров** по их формату
   (AWS, GitHub, Slack, …), а не «строку, похожую на пароль». Эти заглушки не
   подходят ни под один детектор: прогон по всему репозиторию с самым широким
   фильтром `--results=verified,unknown,unverified` даёт **0 находок**.
2. Фильтр `verified,unknown` дополнительно отсекает `unverified` — то, что
   детектор нашёл, но провайдер **явно ответил «невалидно»**. Живой секрет
   (`verified`) и секрет, который не удалось проверить (`unknown`), остаются.

Обратная сторона: подложенный фейковый AWS-ключ в этом режиме тоже будет
отфильтрован как `unverified`. Поэтому в `06-trufflehog-local.sh` есть флаг
`--all`, добавляющий `unverified` — им и демонстрируется срабатывание
(см. [CHECKLIST.MD](CHECKLIST.MD)).

## Trivy — уязвимости, секреты, misconfig

Джоба `trivy` — четыре шага, и у каждого своя роль:

| Шаг | Что делает | `exit-code` |
|---|---|---|
| Отчёт `fs` | `vuln,secret,misconfig`, HIGH+CRITICAL, вывод таблицей | `0` — только смотрим |
| **Гейт** | `vuln`, только CRITICAL, только `ignore-unfixed` | `1` — валит пайплайн |
| SARIF | тот же отчёт в SARIF → Code scanning | `0` |
| Образ ДЗ 8 | `ghcr.io/fastrapier/hw8:latest` | `0`, `continue-on-error` |

**Почему misconfig не валит пайплайн.** В учебных чартах и манифестах 46
находок HIGH (см. ниже) — не баги, а сознательные упрощения учебного стенда.
Если бы они валили сборку, пайплайн был бы красным всегда, а красный всегда —
это то же самое, что выключенный. Они остаются видимыми в логе и в Security tab.

**Почему гейт узкий.** Гейт должен ловить то, на что можно реально
отреагировать: `ignore-unfixed` оставляет только уязвимости, где апстрим уже
выпустил исправление, а `severity: CRITICAL` — только то, из-за чего стоит
останавливать работу.

**Почему шаг с образом `continue-on-error`.** Образ `hw8:latest` собирает
пайплайн ДЗ 8, который ещё не смержен в `main`. Пока образа в GHCR нет, шаг
ожидаемо не находит его. Отключать проверку совсем — значит забыть её включить.

**Загрузка SARIF — `continue-on-error`.** Code scanning доступен не во всех
тарифах; если загрузка недоступна, отчёт остаётся в логе первого шага, и
ронять из-за этого весь пайплайн незачем.

На момент сдачи в этом репозитории Code scanning **не включён**, и шаг
загрузки действительно падает с `Resource not accessible by integration` —
`continue-on-error` его гасит, джоба остаётся зелёной. Чтобы находки поехали
во вкладку Security, Code scanning надо включить в настройках репозитория
(Settings → Code security). Пока он выключен, полный отчёт смотрится в логе
первого шага джобы.

### `.trivyignore.yaml` — реестр принятых рисков

Формат YAML выбран вместо построчного `.trivyignore` ради двух обязательных
полей у каждой записи: `statement` (почему риск принят) и `expired_at` (когда
исключение перестанет действовать). Бессрочных исключений в файле нет.

Важная деталь, которая стоила отладки: **YAML-вариант не подхватывается
автоматически**. Обычный `.trivyignore` Trivy находит сам, а для
`.trivyignore.yaml` нужен явный `--ignorefile` (в CI — вход `trivyignores`).
Без него гейт падал, хотя файл лежал на месте.

Подавленные находки не прячутся: отчётный шаг идёт с `--show-suppressed`
(в CI — `TRIVY_SHOW_SUPPRESSED=true`), и Trivy печатает их отдельной таблицей
вместе с текстом обоснования.

## SonarQube — статический анализ

### Чарт и его сюрпризы

Чарт `sonarqube/sonarqube` **2026.4.1**, values — `helm/sonarqube-values.yaml`.

| Параметр | Значение | Почему |
|---|---|---|
| `community.enabled` | `true` | Community Build — бесплатная редакция. Без флага чарт тянет образ платной. `edition` не задаём |
| `monitoringPasscode` | через `--set` | **Обязателен**: без него чарт не проходит собственную валидацию. Секрет — значит не в values, а из Keychain |
| `jdbcOverwrite.enabled` | `false` | С версии чарта 2026.1.0 **зависимость от PostgreSQL удалена**, из коробки встроенная H2. Ключа `postgresql.enabled` больше нет |
| `persistence.enabled` | `true`, 5Gi | H2 держит данные в `/opt/sonarqube/data`: без PVC проект и токены пропадут при перезапуске пода |
| `resources.limits.ephemeral-storage` | `4096M` | Дефолт чарта — `512000M` (~512 ГБ). На minikube такой под не планируется **никогда** |
| `initSysctl.enabled` | `true` | Встроенному Elasticsearch нужен `vm.max_map_count`. initContainer privileged — на minikube разрешено; при restricted PSA выставить `false` |
| `ingress` | `sonarqube-hw10.local` | `hosts[].name` (не `host`), `ingressClassName` — на уровне `ingress` |
| probes | `initialDelaySeconds: 60` | Первый старт распаковывает бандл и поднимает ES, дефолтных порогов не хватает |

`fullnameOverride` не задан, поэтому Service называется `<release>-<chart>` —
**`sonarqube-sonarqube:9000`**.

Пароль админа меняется не чартом (`setAdminPassword`), а через API в
`03-configure-sonarqube.sh`: скрипту всё равно нужно ходить в API за проектом и
токеном, а один механизм вместо двух проще и позволяет положить сгенерированный
пароль в Keychain.

### Почему джоба на self-hosted раннере

SonarQube живёт в minikube на ноутбуке. У GitHub-hosted раннера до него нет
сети — ровно та же проблема, что у джобы `deploy` в ДЗ 8. Решение оттуда же:

```yaml
runs-on: ${{ vars.HW8_RUNNER || 'ubuntu-latest' }}
```

`HW8_RUNNER` — метка self-hosted раннера (ARC внутри кластера, ДЗ 8 часть 2).
Fallback обязателен: без него джоба висела бы в очереди до таймаута GitHub
каждый раз, когда minikube выключен.

Первый шаг проверяет секреты `SONAR_TOKEN` и `SONAR_HOST_URL` **через env**, а
не подстановкой в `if:` — так значение не попадает в текст скрипта. Нет
секретов → `::warning::` и честный пропуск вместо падения.

### Два варианта `SONAR_HOST_URL`

| Где раннер | Значение |
|---|---|
| Self-hosted внутри кластера (ДЗ 8) | `http://sonarqube-sonarqube.k8s-hw10.svc:9000` |
| Раннер вне кластера | внешний адрес, например `https://sonarqube.example.com` |

Внутрикластерный адрес снаружи не резолвится, поэтому GitHub-hosted раннеру он
бесполезен — на это и рассчитан пропуск джобы.

### Quality Gate — `continue-on-error`

На коде четырёх сданных ДЗ Quality Gate почти наверняка `FAILED`. Задача ДЗ —
настроить анализ и видеть результат, а не привести задним числом всё
к чистому листу. Статус виден в логе джобы и в UI.

## Результаты первого сканирования

Прогон по репозиторию на момент сдачи (без чувствительных данных).

### TruffleHog — чисто

| Что сканировали | Объём | Находки |
|---|---|---|
| Вся история ветки | 833 фрагмента, ~914 КБ | **0** |
| Рабочее дерево | 175 фрагментов, ~315 КБ | **0** |

Ноль сохраняется даже с `--results=verified,unknown,unverified`, то есть
в репозитории нет **ни одной** строки, похожей на учётные данные известного
провайдера. Исключений для TruffleHog не понадобилось.

### Trivy — уязвимости зависимостей

18 находок HIGH+CRITICAL, **у всех есть исправленная версия**:

| Модуль | Пакет | Установлено → Фикс | Находки |
|---|---|---|---|
| `hw1-2/go.mod` | `github.com/jackc/pgx/v5` | v5.5.5 → 5.9.0 | 2 CRITICAL |
| `hw1-2/go.mod` | `golang.org/x/crypto` | v0.17.0 → 0.55.0 | 1 CRITICAL + 11 HIGH |
| `hw1-2/go.mod` | `golang.org/x/text` | v0.14.0 → 0.39.0 | 1 HIGH |
| `hw-3/go/go.mod` | `github.com/rabbitmq/amqp091-go` | v1.10.0 → 1.13.0 | 1 HIGH |
| `hw-4/go.mod` | `github.com/rabbitmq/amqp091-go` | v1.10.0 → 1.13.0 | 1 HIGH |

Все три CRITICAL — в `hw1-2`, сданном и замороженном ДЗ. Подъём драйвера БД и
`golang.org/x/crypto` тянет перепроверку миграций и относится к ДЗ 1-2, а не
к ДЗ про безопасность, поэтому они внесены в `.trivyignore.yaml` с
обоснованием и датой истечения `2027-01-01`. 15 HIGH не подавлены и остаются
в отчёте: подъём `golang.org/x/crypto` в ДЗ 1-2 закроет 12 из них разом.

### Trivy — misconfig

46 находок HIGH, всего три правила:

| Правило | Раз | Суть |
|---|---|---|
| `KSV-0118` | 26 | Дефолтный security context (разрешён root) |
| `KSV-0014` | 13 | `readOnlyRootFilesystem` не выставлен |
| `DS-0002` | 7 | В Dockerfile не задан `USER` — образ работает root-ом |

Это известный долг учебных манифестов и Dockerfile-ов прошлых ДЗ. Правки
затронули бы четыре сданных ДЗ, поэтому находки оставлены видимыми, но
не блокирующими.

Отдельно: Trivy **не смог разобрать чарт `hw-4/.helm`** — шаблоны написаны под
werf и ссылаются на `.Values.werf.image`, которого при обычном рендере нет
(`nil pointer`). Чарт просто пропускается с предупреждением.

### Trivy — секреты

**0 находок.** Собственный secret-сканер Trivy, как и TruffleHog, не считает
dev-заглушки прошлых ДЗ учётными данными.

## Быстрый старт

```bash
# Только pre-commit (кластер не нужен)
cd hw-10 && ./scripts/01-precommit.sh

# Всё, включая SonarQube в minikube
minikube start
minikube tunnel            # отдельный терминал
cd hw-10 && ./init.sh      # ~10-15 минут (первый старт SonarQube долгий)
```

После `init.sh` секреты репозитория **не выставляются автоматически** —
скрипт печатает готовые команды. Разом: `./scripts/03-configure-sonarqube.sh --set-secrets`.

## Доступ к UI

| Сервис | URL |
|---|---|
| SonarQube | http://sonarqube-hw10.local |

Логин `admin`, пароль генерируется и лежит в Keychain:

```bash
security find-generic-password -a fastrapier -s sonarqube-hw10 -w
```

> Требуется `minikube tunnel` и запись в `/etc/hosts` (создаётся скриптом).

## Как читать отчёты

| Где | Что видно |
|---|---|
| Логи джоб в Actions | полные таблицы Trivy, находки TruffleHog |
| Job summary | режим сканирования TruffleHog, раннер и статус SonarQube |
| Security → Code scanning | находки Trivy как алерты с привязкой к строкам. Сейчас Code scanning в репозитории выключен — шаг загрузки гасится `continue-on-error` |
| SonarQube UI | `http://sonarqube-hw10.local/dashboard?id=k8s-hw` — баги, code smells, покрытие |
| Локально | `scripts/04..06-*.sh` — те же проверки без CI |

## Полезные команды

```bash
# Поды и ресурсы SonarQube
kubectl get pods -n k8s-hw10
kubectl get pvc,svc,ingress -n k8s-hw10
kubectl logs -f statefulset/sonarqube-sonarqube -n k8s-hw10

# Статус SonarQube через port-forward
kubectl port-forward svc/sonarqube-sonarqube -n k8s-hw10 9000:9000 &
curl -s localhost:9000/api/system/status

# Секреты из Keychain
security find-generic-password -a fastrapier -s sonarqube-hw10 -w        # пароль admin
security find-generic-password -a fastrapier -s sonarqube-hw10-token -w  # CI-токен

# Локальные прогоны
./scripts/05-trivy-local.sh
./scripts/06-trufflehog-local.sh
./scripts/06-trufflehog-local.sh --all   # включая unverified

# pre-commit
pre-commit run --all-files
pre-commit run trufflehog

# Запустить пайплайн вручную
gh workflow run hw10-security.yml
gh run list --workflow hw10-security.yml
```

## Чеклист для защиты

Пошаговый план демонстрации: **[CHECKLIST.MD](CHECKLIST.MD)**

## Очистка

```bash
./teardown.sh
kubectl delete namespace k8s-hw10
```
