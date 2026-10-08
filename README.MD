# Kubernetes — домашние задания

```
Студеникин Даниил 11-312
https://t.me/imperial_dan
```

---

## Домашние задания

| # | Тема | Директория | Описание |
|---|---|---|---|
| 1-2 | Helm + Vault | [hw1-2/](hw1-2/) | Helm-чарт приложения, интеграция с HashiCorp Vault (AppRole, helm-secrets) |
| 3 | RabbitMQ + Celery | [hw-3/](hw-3/) | Брокер сообщений, Go Producer/Consumer, Python Celery/Flower/FastAPI |
| 4 | Redis + кэширование | [hw-4/](hw-4/) | Redis, RedisInsight, CacheManager с TTL, кэширование API-запросов |
| 7 | Масштабирование | [hw-7/](hw-7/) | metrics-server, requests/limits, стресс-тесты Locust, HPA + VPA, locust-operator |
| 8 | CI/CD | [hw-8/](hw-8/) | semantic-release, GitHub Actions: тег → сборка образа в GHCR → деплой |
| 9 | Werf | [hw-9/](hw-9/) | Рефакторинг чарта в werf-проект, helm submodules, глобальные values, интеграция с Vault |
| 11 | Мониторинг | [hw-11/](hw-11/) | helmfile, Prometheus + метрики ингресса, Loki + promtail, Grafana с алертингом на SMTP |

| 10 | Безопасность | [hw-10/](hw-10/) | TruffleHog (pre-commit + CI), Trivy, SonarQube в minikube |

---

### ДЗ 1-2: Helm-чарт + Vault

Разработка Helm-чарта для приложения с PostgreSQL, интеграция с HashiCorp Vault для управления секретами.

- Helm-чарты с подчартами (backend, postgres)
- Vault AppRole аутентификация
- helm-secrets + vals для подстановки секретов из Vault

Подробнее: [hw1-2/README.MD](hw1-2/README.MD)

---

### ДЗ 3: RabbitMQ + Celery

Подключение RabbitMQ как брокера сообщений. Два независимых пайплайна обработки задач:

- **Go** — Producer (CronJob) отправляет задачи, Consumer обрабатывает (OpenWeatherMap, NewsAPI)
- **Python** — Celery Worker выполняет задачи, FastAPI предоставляет HTTP API, Flower для мониторинга
- Все секреты хранятся в Vault, аутентификация через AppRole
- Сборка и деплой через werf + GitHub Container Registry
- Идемпотентные скрипты: `init.sh` для развёртывания, `teardown.sh` для очистки

Подробнее: [hw-3/README.MD](hw-3/README.MD) | Чеклист для защиты: [hw-3/CHECKLIST.MD](hw-3/CHECKLIST.MD)

---

### ДЗ 4: Redis и кэширование

Развертывание Redis и RedisInsight, реализация CacheManager с TTL:

- **Redis** — StatefulSet на базе redis-stack-server, Headless Service + LoadBalancer, пароль из Vault
- **RedisInsight** — Helm-чарт heywood8/redisinsight с Ingress
- **CacheManager** — Go-модуль для работы с Redis (Get/Set/Exists + TTL)
- **Кэширование API** — CACHE HIT из Redis или API CALL + CACHE SET с TTL (5 мин погода, 10 мин новости)
- Изолированный namespace `k8s-hw4`

Подробнее: [hw-4/README.MD](hw-4/README.MD) | Чеклист для защиты: [hw-4/CHECKLIST.MD](hw-4/CHECKLIST.MD)

---

### ДЗ 7: Масштабирование

Go API с PostgreSQL под нагрузкой Locust: от начальных лимитов до автомасштабирования.

- **metrics-server** — addon minikube, источник CPU/RAM для `kubectl top`, HPA и VPA
- **requests/limits** — начальные значения по замерам в покое, новые — по критической точке
- **Locust** — тест на GET-эндпоинты API (`/db/requests`, `/db/report`, `/db/stats`),
  настройки в `locust.conf`, ступенчатый поиск максимума пользователей по CSV-отчётам
- **HPA** — `autoscaling/v2`, CPU 70%, 2–6 реплик, быстро вверх / окно стабилизации 300 с вниз
- **VPA** — чарт Fairwinds, `updateMode: "Recreate"`, автоматически меняет requests памяти; HPA использует CPU
- **locust-operator** — `LocustTest` + ConfigMap с `locustfile.py` + Ingress на `load-test-v2-webui:8089`
- Изолированный namespace `k8s-hw7`, сборка и деплой через werf + GHCR

Подробнее: [hw-7/README.MD](hw-7/README.MD) | Чеклист для защиты: [hw-7/CHECKLIST.MD](hw-7/CHECKLIST.MD)

---

### ДЗ 8: CI/CD

Пайплайн в GitHub Actions, где версия образа считается автоматически по Conventional Commits:

- **semantic-release** — считает следующую версию по сообщениям коммитов, создаёт git-тег `vX.Y.Z` и GitHub Release с release notes
- **Сборка образа по тегу** — buildx собирает `ghcr.io/fastrapier/hw8:<version>`, версия и git-sha зашиваются в бинарник через `-ldflags`
- **Деплой по тегу** — `helm upgrade --install` с `--set image.tag=<version>`; тот же чарт используется и локально
- **Приложение** — минимальный Go HTTP-сервис с `GET /healthz` и `GET /version`
- **Свой self-hosted раннер** — Actions Runner Controller ставится двумя OCI-чартами GitHub в minikube (`arc-systems` + `arc-runners`); джоба `deploy` уезжает на него и деплоит изнутри кластера, без kubeconfig в секретах
- На pull request — dry-run версии и сборка образа без push; реальный релиз только при push в `main`
- Изолированный namespace `k8s-hw8`

Workflow: [.github/workflows/hw8-release.yml](.github/workflows/hw8-release.yml)

Подробнее: [hw-8/README.MD](hw-8/README.MD) | Чеклист для защиты: [hw-8/CHECKLIST.MD](hw-8/CHECKLIST.MD)

---

### ДЗ 9: Werf

Приложение из ДЗ 1-2 (Go HTTP API + PostgreSQL) переехало из «чарт + Makefile + helm-secrets»
в самодостаточный werf-проект:

- **werf-проект** — `werf.yaml` с тремя образами (app, cron, migrations) и исходниками рядом
- **Helm submodules** — сабчарты `backend` и `postgres` в `.helm/charts/`, `dependencies` с `condition`
- **Глобальные values** — порты, имена сервисов, хост Ingress и слоты под секреты в `global`
- **Интеграция с Vault** — один скрипт: AppRole login → docker-токен → `werf cr login` →
  секреты через `vals` → `werf converge --values`
- В репозитории нет ни токена, ни пароля: только `ref+vault://`-ссылки
- Изолированный namespace `k8s-hw9`, образы `ghcr.io/fastrapier/hw9`

Подробнее: [hw-9/README.MD](hw-9/README.MD) | Чеклист для защиты: [hw-9/CHECKLIST.MD](hw-9/CHECKLIST.MD)

---

### ДЗ 10: Безопасность

Три инструмента на трёх рубежах: секреты, уязвимости зависимостей, качество кода.

- **TruffleHog** — в pre-commit (секрет не попадает в историю) и в пайплайне: на pull request сканируется дифф `base..head`, на push в `main` — вся история ветки
- **Trivy** — `vuln` + `secret` + `misconfig` по всему репозиторию, отчёт в лог и в SARIF (Security tab). Гейт узкий и потому осмысленный: только CRITICAL с доступным фиксом; принятые риски — в `.trivyignore.yaml` с обоснованием и датой истечения
- **SonarQube** (Community Build) — Helm-чарт в namespace `k8s-hw10`, Ingress `sonarqube-hw10.local`, покрытие Go в отчёте. Джоба выполняется на self-hosted раннере из ДЗ 8: у GitHub-hosted нет сети до minikube
- Конфиги инструментов (`.pre-commit-config.yaml`, `sonar-project.properties`, `.trivyignore.yaml`, workflow) лежат в корне репозитория — инструменты ищут их только там
- Секреты в репозиторий не попадают: пароль админа и CI-токен генерируются скриптом и хранятся в macOS Keychain

Подробнее: [hw-10/README.MD](hw-10/README.MD) | Чеклист для защиты: [hw-10/CHECKLIST.MD](hw-10/CHECKLIST.MD)

---

### ДЗ 11: Мониторинг

Стек мониторинга в minikube, развёрнутый одной командой через helmfile:

- **helmfile** — пять релизов декларативно в одном файле: репозитории, пинованные версии чартов, values и порядок установки через `needs`
- **Prometheus** — чарт `kube-prometheus-stack` (Operator + CRD `ServiceMonitor`), Alertmanager, node-exporter, kube-state-metrics
- **Метрики ингресса** — свой мини-чарт `charts/ingress-metrics`: Service на порт 10254 контроллера в namespace `ingress-nginx` + ServiceMonitor в `k8s-hw11`
- **Loki + promtail** — логи всех подов кластера, Loki в режиме SingleBinary на filesystem
- **Grafana** — datasources, дашборды и алертинг целиком через provisioning; contact point на email, SMTP-токен только из Keychain
- Изолированный namespace `k8s-hw11`, идемпотентные `init.sh` / `teardown.sh`

Подробнее: [hw-11/README.MD](hw-11/README.MD) | Чеклист для защиты: [hw-11/CHECKLIST.MD](hw-11/CHECKLIST.MD)
