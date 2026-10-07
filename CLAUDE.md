# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Что это

Учебный репозиторий с домашними заданиями курса по Kubernetes / Enterprise-разработке.
Каждое ДЗ — самостоятельная директория (`hw1-2/`, `hw-3/`, `hw-4/`, далее `hw-N/`) со своим
кодом, чартами и скриптами развёртывания. Общего кода между ДЗ нет: новое задание копирует
и развивает предыдущее. Корневой `README.MD` — оглавление с таблицей ДЗ.

Вся документация репозитория на русском. Новые README, чеклисты и описания PR — тоже на русском.

## Формат нового ДЗ

Ориентир — `hw-4/` (самый свежий и наиболее вычищенный вариант). Директория `hw-N/` содержит:

- `TASK.MD` — исходный текст задания (не редактировать, это входные данные).
- `README.MD` — архитектура ASCII-схемой, структура проекта, быстрый старт, доступ к UI,
  полезные команды, очистка.
- `CHECKLIST.MD` — пошаговый план демонстрации для защиты.
- `init.sh` / `teardown.sh` — идемпотентные точки входа; `init.sh` только последовательно
  вызывает скрипты, вся логика в `scripts/`.
- `scripts/common.sh` — константы (`NAMESPACE`, хосты, `GHCR_REPO`) и общие функции
  (`ensure_minikube`, `add_host`, `vault_login`, `create_vault_approle_secret`,
  `create_ghcr_pull_secret`, `helm_cleanup_pending`, `add_helm_repo`).
- `scripts/0N-<шаг>.sh` — нумерованные шаги, каждый `set -euo pipefail` + `source common.sh`.
- `werf.yaml` + `.helm/` (Chart.yaml, values.yaml, templates/) — сборка и деплой приложения.
- `docker/*.Dockerfile` — по образу на компонент.

Устоявшиеся соглашения:

- Свой namespace на ДЗ: `k8s-hw4` в hw-4 (в hw-3 ещё был общий `k8s-hw` — для новых ДЗ
  использовать суффикс номера).
- Хосты Ingress с суффиксом ДЗ: `vault-hw4.local`, `rabbitmq-hw4.local`,
  `redisinsight-hw4.local`; записи в `/etc/hosts` добавляет и удаляет сам скрипт (`add_host`).
- Секреты только через Vault (dev-режим, root-токен `root`), приложение аутентифицируется
  по AppRole: `VAULT_ROLE_ID` + `VAULT_SECRET_ID` из K8s Secret `vault-approle`.
  Путь KV v2 задаётся как `secret/<name>`, префикс `/v1/secret/data/` добавляет клиент.
- Образы — `ghcr.io/fastrapier/hwN`; токен GHCR берётся из macOS Keychain
  (`security find-generic-password -a fastrapier -s ghcr.io -w`), из него же делается
  `imagePullSecret ghcr-pull-secret`. Токены в репозиторий и в `.env` не попадают.
- Целевая среда — minikube на macOS; для Ingress нужен `minikube tunnel` в отдельном терминале.
- Скрипты идемпотентны: повторный запуск `init.sh` не должен падать
  (`--dry-run=client -o yaml | kubectl apply -f -`, `helm upgrade --install`, проверки
  существования репо/релиза).

## Команды

Развёртывание и очистка ДЗ:

```bash
minikube start
minikube tunnel            # отдельный терминал, нужен для Ingress
cd hw-4 && ./init.sh       # полное развёртывание, ~7 минут
./teardown.sh              # снос (namespace и PVC остаются)
kubectl delete namespace k8s-hw4
```

Go-модули (у каждого ДЗ свой `go.mod`, корневого модуля нет):

```bash
cd hw-4     && go build ./... && go vet ./...
cd hw-3/go  && go build ./... && go vet ./...
cd hw1-2    && go build ./... && go vet ./... && go test ./...
```

Тесты есть только в `hw1-2` (`internal/handler/server_test.go`):
`cd hw1-2 && go test ./internal/handler -run TestHealthz -v`.

Helm/werf:

```bash
cd hw-4 && werf render --dev --stub-tags        # проверка рендера без кластера и без сборки
cd hw-4 && werf converge --dev --repo ghcr.io/fastrapier/hw4 --namespace k8s-hw4
cd hw-4 && werf dismiss --namespace k8s-hw4
helm lint hw1-2/helm/app                        # обычные чарты
```

`helm lint`/`helm template` к `.helm/` werf-проектов не применимы: шаблоны используют
`.Values.werf.image.*`, которые подставляет werf, — проверять только через `werf render`.

`hw1-2` собирается через `make` (`make build`, `make test`, `make deploy`, `make vault-install`,
`make undeploy`) — это более старый, ручной вариант без werf.

## Стек

Go 1.26 (в `hw1-2` — 1.24), Python 3 (Celery 5.4 + FastAPI + Flower в `hw-3/celery`),
Kubernetes (minikube), Helm, werf, HashiCorp Vault (AppRole), RabbitMQ, Redis
(redis-stack-server + RedisInsight), PostgreSQL (`hw1-2`), GitHub Container Registry.

## Git-процесс

- Ветка на каждое ДЗ (`hw-4`, `vault`, …) → PR в `main`. Не мержить PR и не пушить в `main`
  без явной просьбы.
- После мержа ДЗ добавляется в корневой `README.MD`: строка в таблицу и секция
  `### ДЗ N: <тема>` по образцу существующих, со ссылками на `README.MD` и `CHECKLIST.MD`.
- Начиная с ДЗ 8 в репозитории появляется semantic-release, поэтому все новые коммиты
  оформляются по Conventional Commits со скоупом ДЗ: `feat(hw-8): ...`, `fix(hw-8): ...`,
  `docs: ...`.

## Замечания для Claude

- Рабочие документы (планы, разборы, отчёты, заметки) не создавать в репозитории —
  только вне рабочего дерева git.
- Не оставлять в коде комментарии о факте правки («теперь мы…», «раньше было…») и не
  дублировать комментарием то, что видно из кода строкой ниже.
- Хардкод секретов недопустим: пароли и API-ключи читаются из Vault, значения в
  `README.MD`/`CHECKLIST.MD` — только dev-заглушки для локального minikube.
