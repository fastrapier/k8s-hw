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
