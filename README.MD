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

### ДЗ 10: Безопасность

Три инструмента на трёх рубежах: секреты, уязвимости зависимостей, качество кода.

- **TruffleHog** — в pre-commit (секрет не попадает в историю) и в пайплайне: на pull request сканируется дифф `base..head`, на push в `main` — вся история ветки
- **Trivy** — `vuln` + `secret` + `misconfig` по всему репозиторию, отчёт в лог и в SARIF (Security tab). Гейт узкий и потому осмысленный: только CRITICAL с доступным фиксом; принятые риски — в `.trivyignore.yaml` с обоснованием и датой истечения
- **SonarQube** (Community Build) — Helm-чарт в namespace `k8s-hw10`, Ingress `sonarqube-hw10.local`, покрытие Go в отчёте. Джоба выполняется на self-hosted раннере из ДЗ 8: у GitHub-hosted нет сети до minikube
- Конфиги инструментов (`.pre-commit-config.yaml`, `sonar-project.properties`, `.trivyignore.yaml`, workflow) лежат в корне репозитория — инструменты ищут их только там
- Секреты в репозиторий не попадают: пароль админа и CI-токен генерируются скриптом и хранятся в macOS Keychain

Подробнее: [hw-10/README.MD](hw-10/README.MD) | Чеклист для защиты: [hw-10/CHECKLIST.MD](hw-10/CHECKLIST.MD)
