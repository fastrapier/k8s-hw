APP_NAME = k8s-test-backend-app
VERSION ?= latest
IMAGE_REPO ?= fastrapier1/k8s-test-backend-app
IMAGE = $(IMAGE_REPO):$(VERSION)
MIGRATIONS_IMAGE_REPO ?= fastrapier1/k8s-test-backend-migrations
MIGRATIONS_IMAGE = $(MIGRATIONS_IMAGE_REPO):$(VERSION)
MIGRATIONS_JOB_NAME = k8s-test-backend-migrations
CRON_IMAGE_REPO ?= fastrapier1/k8s-test-backend-cron
CRON_IMAGE = $(CRON_IMAGE_REPO):$(VERSION)
SWAGGER_JSON = docs/swagger.json
SWAGGER_BIN = $(shell go env GOPATH)/bin/swagger
LDFLAGS = -X k8s-hw/internal/handler.Version=$(VERSION)
K8S_NAMESPACE = k8s-hw
CURRENT_CONTEXT = $(shell kubectl config current-context 2>/dev/null)

.PHONY: all swagger build run clean docker docker-push docker-migrations docker-migrations-push docker-cron docker-cron-push test dashboard-token deploy undeploy migrations-job

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
	@echo "Сборка образа приложения $(IMAGE) (docker/app.Dockerfile)"
	docker build -f docker/app.Dockerfile --build-arg VERSION=$(VERSION) -t $(IMAGE) .

# Публикация образа приложения

docker-push: docker
	@echo "Публикация образа приложения $(IMAGE)"
	docker push $(IMAGE)

# Сборка Docker-образа миграций (golang-migrate + migrations/*.sql)
# Использование: make docker-migrations VERSION=1.2.3

docker-migrations:
	@echo "Сборка образа миграций $(MIGRATIONS_IMAGE) (docker/migrations.Dockerfile)"
	docker build -f docker/migrations.Dockerfile -t $(MIGRATIONS_IMAGE) .

# Публикация образа миграций

docker-migrations-push: docker-migrations
	@echo "Публикация образа миграций $(MIGRATIONS_IMAGE)"
	docker push $(MIGRATIONS_IMAGE)

# Сборка Docker-образа для CronJob
# Использование: make docker-cron VERSION=1.2.3

docker-cron:
	@echo "Сборка cron образа $(CRON_IMAGE) (docker/cron.Dockerfile)"
	docker build -f docker/cron.Dockerfile --build-arg VERSION=$(VERSION) -t $(CRON_IMAGE) .

# Публикация образа для CronJob

docker-cron-push: docker-cron
	@echo "Публикация cron образа $(CRON_IMAGE)"
	docker push $(CRON_IMAGE)

# Запуск (пере)создания Kubernetes Job для миграций
# 1. Удаляем старый job (если был)
# 2. Применяем манифест
# 3. Патчим image с текущим тегом
# 4. Ждём завершения (успех или ошибка)

migrations-job:
	@if [ "$(CURRENT_CONTEXT)" != "docker-desktop" ]; then \
		echo "ОШИБКА: kubectl context должен быть 'docker-desktop' (текущий: $(CURRENT_CONTEXT))" >&2; exit 1; \
	fi
	@echo "Применение миграций (образ: $(MIGRATIONS_IMAGE))"
	kubectl delete job $(MIGRATIONS_JOB_NAME) -n $(K8S_NAMESPACE) --ignore-not-found
	kubectl apply -f k8s/db/migrations-job.yaml
	kubectl patch job $(MIGRATIONS_JOB_NAME) -n $(K8S_NAMESPACE) --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"$(MIGRATIONS_IMAGE)"}]'
	@echo "Ожидание завершения StatefulSet Postgres (если разворачивается впервые)"
	kubectl rollout status statefulset/postgres-sts -n $(K8S_NAMESPACE) --timeout=300s || echo "WARN: rollout status postgres-sts не успешен (может быть уже готов)"
	@echo "Ожидание выполнения job миграций..."
	kubectl wait --for=condition=complete --timeout=180s job/$(MIGRATIONS_JOB_NAME) -n $(K8S_NAMESPACE) || (echo "Миграции не завершились успешно" && kubectl logs job/$(MIGRATIONS_JOB_NAME) -n $(K8S_NAMESPACE) ; exit 1)
	@echo "Миграции применены"

# Полный деплой: build+push обоих образов, манифесты, миграции, приложение

deploy: docker-push docker-migrations-push docker-cron-push
	@if [ "$(CURRENT_CONTEXT)" != "docker-desktop" ]; then \
		echo "ОШИБКА: kubectl context должен быть 'docker-desktop' (текущий: $(CURRENT_CONTEXT))" >&2; exit 1; \
	fi
	@echo "Применение основных манифестов (namespace/db/pvc)"
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/db/config-map.yaml
	kubectl apply -f k8s/db/secrets.yaml
	kubectl apply -f k8s/db/service.yaml
	kubectl apply -f k8s/db/db.yaml
	kubectl apply -f k8s/pvc.yaml
	$(MAKE) migrations-job
	@echo "Применение application манифестов"
	kubectl apply -f k8s/app
	kubectl set image deployment/$(APP_NAME) $(APP_NAME)=$(IMAGE) -n $(K8S_NAMESPACE) --record || true
	kubectl rollout status deployment/$(APP_NAME) -n $(K8S_NAMESPACE) --timeout=180s
	@echo "Применение CronJob"
	kubectl apply -f k8s/app/cronjob.yaml
	kubectl patch cronjob k8s-test-backend-cron -n $(K8S_NAMESPACE) --type='json' -p='[{"op":"replace","path":"/spec/jobTemplate/spec/template/spec/containers/0/image","value":"$(CRON_IMAGE)"}]'
	@echo "Готово. Pods:";
	kubectl get pods -n $(K8S_NAMESPACE) -l app=$(APP_NAME)

# Удаление всех ресурсов (обратно к чистому состоянию)

undeploy:
	@if [ "$(CURRENT_CONTEXT)" != "docker-desktop" ]; then \
		echo "ОШИБКА: kubectl context должен быть 'docker-desktop' (текущий: $(CURRENT_CONTEXT))" >&2; exit 1; \
	fi
	@echo "Удаление ресурсов в namespace $(K8S_NAMESPACE)"
	- kubectl delete cronjob k8s-test-backend-cron -n $(K8S_NAMESPACE) --ignore-not-found
	- kubectl delete -f k8s/app -n $(K8S_NAMESPACE) --ignore-not-found
	- kubectl delete job $(MIGRATIONS_JOB_NAME) -n $(K8S_NAMESPACE) --ignore-not-found
	- kubectl delete -f k8s/db -n $(K8S_NAMESPACE) --ignore-not-found
	- kubectl delete -f k8s/pvc.yaml -n $(K8S_NAMESPACE) --ignore-not-found
	@echo "Удаление namespace..."
	- kubectl delete -f k8s/namespace.yaml --ignore-not-found
	@echo "Undeploy завершён."

# Токен для Kubernetes Dashboard

dashboard-token:
	@chmod +x scripts/gen-dashboard-token.sh
	@./scripts/gen-dashboard-token.sh
