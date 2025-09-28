APP_NAME = k8s-test-backend-app
VERSION ?= latest
IMAGE_REPO ?= fastrapier1/k8s-test-backend-app
IMAGE = $(IMAGE_REPO):$(VERSION)
MIGRATIONS_IMAGE_REPO ?= fastrapier1/k8s-test-backend-migrations
MIGRATIONS_IMAGE = $(MIGRATIONS_IMAGE_REPO):$(VERSION)
MIGRATIONS_JOB_NAME = k8s-test-backend-migrations
CRON_IMAGE_REPO ?= fastrapier1/k8s-test-backend-cron
CRON_IMAGE = $(CRON_IMAGE_REPO):$(VERSION)
CRON_JOB_NAME = k8s-test-backend-cron
INGRESS_NAME ?= app-ingress
INGRESS_HOST ?= k8s-hw.local
K8S_CONTEXT ?= docker-desktop
INGRESS_CONTROLLER_MANIFEST ?= https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/cloud/deploy.yaml
TLS_SECRET_NAME ?= k8s-hw-tls
CERTS_DIR ?= certs
TLS_KEY_FILE ?= $(CERTS_DIR)/tls.key
TLS_CRT_FILE ?= $(CERTS_DIR)/tls.crt
SWAGGER_JSON = docs/swagger.json
SWAGGER_BIN = $(shell go env GOPATH)/bin/swagger
LDFLAGS = -X k8s-hw/internal/handler.Version=$(VERSION)
K8S_NAMESPACE = k8s-hw
# kubectl с заданным контекстом
KCTL = kubectl --context $(K8S_CONTEXT)
# kubectl с контекстом и namespace
KCTL_NS = $(KCTL) -n $(K8S_NAMESPACE)

# Цвета для форматирования вывода
RESET=\033[0m
GREEN=\033[0;32m
YELLOW=\033[0;33m
BLUE=\033[1;34m
RED=\033[0;31m
MAGENTA=\033[0;35m

# Префиксы (только цвет + тег, без сброса; сброс в конце строки)
P_INFO=$(BLUE)[INFO]
P_STEP=$(YELLOW)[STEP]
P_OK=$(GREEN)[OK]
P_ERR=$(RED)[ERR]
P_BUILD=$(MAGENTA)[BUILD]

.PHONY: all swagger build run clean docker docker-push docker-migrations docker-migrations-push docker-cron docker-cron-push ingress test dashboard-token deploy undeploy migrations-job

all: build

$(SWAGGER_BIN):
	GO111MODULE=on go install github.com/go-swagger/go-swagger/cmd/swagger@v0.32.3

swagger: $(SWAGGER_BIN)
	$(SWAGGER_BIN) generate spec -o $(SWAGGER_JSON) --scan-models

build: swagger
	go build -ldflags "$(LDFLAGS)" -o bin/$(APP_NAME) .

run: build
	./bin/$(APP_NAME)

test: swagger
	go test ./...

clean:
	rm -rf bin
	rm -f $(SWAGGER_JSON)

# Сборка Docker-образа приложения
# Использование: make docker VERSION=1.2.3

docker: swagger
	@printf '%b\n' "$(P_BUILD) Сборка образа приложения $(IMAGE) (docker/app.Dockerfile)$(RESET)"
	@docker build -f docker/app.Dockerfile --build-arg VERSION=$(VERSION) -t $(IMAGE) .

# Публикация образа приложения

docker-push: docker
	@printf '%b\n' "$(P_STEP) Публикация образа приложения $(IMAGE)$(RESET)"
	@docker push $(IMAGE)

# Сборка Docker-образа миграций (golang-migrate + migrations/*.sql)
# Использование: make docker-migrations VERSION=1.2.3

docker-migrations:
	@printf '%b\n' "$(P_BUILD) Сборка образа миграций $(MIGRATIONS_IMAGE) (docker/migrations.Dockerfile)$(RESET)"
	@docker build -f docker/migrations.Dockerfile -t $(MIGRATIONS_IMAGE) .

# Публикация образа миграций

docker-migrations-push: docker-migrations
	@printf '%b\n' "$(P_STEP) Публикация образа миграций $(MIGRATIONS_IMAGE)$(RESET)"
	@docker push $(MIGRATIONS_IMAGE)

# Сборка Docker-образа для CronJob
# Использование: make docker-cron VERSION=1.2.3

docker-cron:
	@printf '%b\n' "$(P_BUILD) Сборка cron образа $(CRON_IMAGE) (docker/cron.Dockerfile)$(RESET)"
	@docker build -f docker/cron.Dockerfile --build-arg VERSION=$(VERSION) -t $(CRON_IMAGE) .

# Публикация образа для CronJob

docker-cron-push: docker-cron
	@printf '%b\n' "$(P_STEP) Публикация cron образа $(CRON_IMAGE)$(RESET)"
	@docker push $(CRON_IMAGE)

# Запуск (пере)создания Kubernetes Job для миграций
# 1. Удаляем старый job (если был)
# 2. Применяем манифест
# 3. Патчим image с текущим тегом
# 4. Ждём завершения (успех или ошибка)

migrations-job:
	@printf '%b\n' "$(P_INFO) Миграции context=$(K8S_CONTEXT) ns=$(K8S_NAMESPACE)$(RESET)"
	@$(KCTL_NS) delete job $(MIGRATIONS_JOB_NAME) --ignore-not-found
	@$(KCTL_NS) apply -f k8s/db/migrations-job.yaml
	@printf '%b\n' "$(P_STEP) Ожидание StatefulSet Postgres$(RESET)"
	@$(KCTL_NS) rollout status statefulset/postgres-sts --timeout=300s || printf '%b\n' "$(P_ERR) WARN: rollout postgres-sts не успешен$(RESET)"
	@printf '%b\n' "$(P_STEP) Ожидание выполнения job миграций$(RESET)"
	@$(KCTL_NS) wait --for=condition=complete --timeout=180s job/$(MIGRATIONS_JOB_NAME) || (printf '%b\n' "$(P_ERR) Миграции не завершились$(RESET)" && $(KCTL_NS) logs job/$(MIGRATIONS_JOB_NAME) ; exit 1)
	@printf '%b\n' "$(P_OK) Миграции применены$(RESET)"

# Полный деплой: build+push обоих образов, манифесты, миграции, приложение

deploy: docker-push docker-migrations-push docker-cron-push
	@printf '%b\n' "$(P_INFO) DEPLOY context=$(K8S_CONTEXT) ns=$(K8S_NAMESPACE) version=$(VERSION)$(RESET)"
	@$(KCTL) apply -f k8s/namespace.yaml
	@$(KCTL_NS) apply -f k8s/db/config-map.yaml
	@$(KCTL_NS) apply -f k8s/db/secrets.yaml
	@$(KCTL_NS) apply -f k8s/db/service.yaml
	@$(KCTL_NS) apply -f k8s/db/db.yaml
	@$(KCTL_NS) apply -f k8s/pvc.yaml
	@$(MAKE) migrations-job
	@printf '%b\n' "$(P_STEP) Применение application манифестов$(RESET)"
	@$(KCTL_NS) apply -f k8s/app/config-map.yaml
	@$(KCTL_NS) apply -f k8s/app/secret.yaml
	@$(KCTL_NS) apply -f k8s/app/service.yaml
	@$(KCTL_NS) apply -f k8s/app/deployment.yaml
	@$(KCTL_NS) rollout status deployment/$(APP_NAME) --timeout=180s
	@printf '%b\n' "$(P_STEP) Применение CronJob$(RESET)"
	@$(KCTL_NS) apply -f k8s/app/cronjob.yaml
	@$(MAKE) .deploy-cert
	@$(MAKE) ingress
	@printf '%b\n' "$(P_OK) Deploy завершён$(RESET)"
	@$(KCTL_NS) get pods -l app=$(APP_NAME)

.deploy-cert:
	@printf '%b\n' "$(P_STEP) Проверка локального TLS сертификата $(TLS_KEY_FILE)/$(TLS_CRT_FILE)$(RESET)"
	@if [ ! -f $(TLS_KEY_FILE) ] || [ ! -f $(TLS_CRT_FILE) ]; then \
		printf '%b\n' "$(P_STEP) Генерация self-signed сертификата (CN=$(INGRESS_HOST))$(RESET)"; \
		mkdir -p $(CERTS_DIR); \
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $(TLS_KEY_FILE) -out $(TLS_CRT_FILE) -subj "/CN=$(INGRESS_HOST)/O=LocalDev" >/dev/null 2>&1; \
		printf '%b\n' "$(P_OK) Созданы $(TLS_KEY_FILE) $(TLS_CRT_FILE)$(RESET)"; \
	else \
		printf '%b\n' "$(P_INFO) Локальные сертификаты уже существуют$(RESET)"; \
	fi
	@if ! $(KCTL_NS) get secret $(TLS_SECRET_NAME) >/dev/null 2>&1; then \
		printf '%b\n' "$(P_STEP) Создание Kubernetes TLS секрета $(TLS_SECRET_NAME)$(RESET)"; \
		$(KCTL_NS) create secret tls $(TLS_SECRET_NAME) --key $(TLS_KEY_FILE) --cert $(TLS_CRT_FILE); \
		printf '%b\n' "$(P_OK) TLS secret $(TLS_SECRET_NAME) создан$(RESET)"; \
	else \
		printf '%b\n' "$(P_INFO) TLS secret $(TLS_SECRET_NAME) уже существует$(RESET)"; \
	fi

ingress:
	@printf '%b\n' "$(P_INFO) Ingress context=$(K8S_CONTEXT) host=$(INGRESS_HOST)$(RESET)"
	@if ! $(KCTL) get deployment ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1; then \
		printf '%b\n' "$(P_STEP) Установка ingress-nginx controller$(RESET)"; \
		$(KCTL) apply -f $(INGRESS_CONTROLLER_MANIFEST); \
		printf '%b\n' "$(P_STEP) Ожидание ingress-nginx-controller$(RESET)"; \
		$(KCTL) rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=240s || printf '%b\n' "$(P_ERR) WARN: ingress-nginx-controller не прогрузился$(RESET)"; \
	else \
		printf '%b\n' "$(P_INFO) Ingress controller уже установлен$(RESET)"; \
	fi
	@$(KCTL_NS) apply -f k8s/app/ingress.yaml
	@$(KCTL_NS) get ingress $(INGRESS_NAME)
	@printf '%b\n' "$(P_STEP) Добавление записи в /etc/hosts (sudo)$(RESET)"
	@LINE_HOST="$(INGRESS_HOST)"; if grep -q "$$LINE_HOST" /etc/hosts; then printf '%b\n' "$(P_INFO) /etc/hosts уже содержит $$LINE_HOST$(RESET)"; else echo "127.0.0.1 $$LINE_HOST" | sudo tee -a /etc/hosts >/dev/null; fi
	@printf '%b\n' "$(P_OK) Ingress готов: https://$(INGRESS_HOST)/$(RESET)"

undeploy:
	@printf '%b\n' "$(P_INFO) UNDEPLOY context=$(K8S_CONTEXT) ns=$(K8S_NAMESPACE)$(RESET)"
	- @$(KCTL_NS) delete ingress $(INGRESS_NAME) --ignore-not-found
	- @$(KCTL_NS) delete cronjob k8s-test-backend-cron --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/app/cronjob.yaml --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/app/deployment.yaml --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/app/service.yaml --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/app/secret.yaml --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/app/config-map.yaml --ignore-not-found
	- @$(KCTL_NS) delete secret $(TLS_SECRET_NAME) --ignore-not-found
	- @$(KCTL_NS) delete job $(MIGRATIONS_JOB_NAME) --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/db/db.yaml --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/db/service.yaml --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/db/secrets.yaml --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/db/config-map.yaml --ignore-not-found
	- @$(KCTL_NS) delete -f k8s/pvc.yaml --ignore-not-found
	@printf '%b\n' "$(P_STEP) Очистка локальных TLS файлов$(RESET)"
	@if [ -f $(TLS_KEY_FILE) ] || [ -f $(TLS_CRT_FILE) ]; then \
		rm -f $(TLS_KEY_FILE) $(TLS_CRT_FILE); \
		printf '%b\n' "$(P_OK) Удалены $(TLS_KEY_FILE) $(TLS_CRT_FILE)$(RESET)"; \
	else \
		printf '%b\n' "$(P_INFO) Локальных TLS файлов нет$(RESET)"; \
	fi
	@if [ -d $(CERTS_DIR) ] && [ -z "`ls -A $(CERTS_DIR)`" ]; then rmdir $(CERTS_DIR) 2>/dev/null || true; fi
	@LINE_HOST="$(INGRESS_HOST)"; \
	printf '%b\n' "$(P_STEP) Очистка /etc/hosts от $$LINE_HOST (если есть)$(RESET)"; \
	if grep -q "$$LINE_HOST" /etc/hosts; then \
		printf '%b\n' "$(P_STEP) Бэкап /etc/hosts -> /tmp/hosts.bak.k8s-hw$(RESET)"; \
		sudo cp /etc/hosts /tmp/hosts.bak.k8s-hw; \
		sudo awk -v h="$$LINE_HOST" '($$1=="127.0.0.1"){ rm=0; for(i=2;i<=NF;i++){ if($$i==h){rm=1; break} } if(rm){next} } {print}' /etc/hosts > /tmp/hosts.new.k8s-hw && sudo mv /tmp/hosts.new.k8s-hw /etc/hosts; \
		printf '%b\n' "$(P_OK) Запись удалена$(RESET)"; \
	else \
		printf '%b\n' "$(P_INFO) Записи $$LINE_HOST не найдено$(RESET)"; \
	fi
	- @$(KCTL) delete -f k8s/namespace.yaml --ignore-not-found || true
	@printf '%b\n' "$(P_OK) Undeploy завершён $(RESET)"

undeploy-full: undeploy
	@printf '%b\n' "$(P_STEP) Дополнительная очистка: удаление ingress-nginx namespace$(RESET)"
	- @$(KCTL) delete namespace ingress-nginx --ignore-not-found
	@printf '%b\n' "$(P_OK) Полная очистка завершена (включая ingress-nginx)$(RESET)"

dashboard-token:
	@printf '%b\n' "$(P_INFO) dashboard-token context=$(K8S_CONTEXT)$(RESET)"
	@chmod +x scripts/gen-dashboard-token.sh
	@K8S_CONTEXT=$(K8S_CONTEXT) ./scripts/gen-dashboard-token.sh
