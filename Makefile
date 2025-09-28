APP_NAME = k8s-test-backend-app
VERSION ?= latest
IMAGE_REPO ?= fastrapier1/k8s-test-backend-app
IMAGE = $(IMAGE_REPO):$(VERSION)
SWAGGER_JSON = docs/swagger.json
SWAGGER_BIN = $(shell go env GOPATH)/bin/swagger
LDFLAGS = -X k8s-hw/internal/handler.Version=$(VERSION)
K8S_NAMESPACE = k8s-hw
CURRENT_CONTEXT = $(shell kubectl config current-context 2>/dev/null)

.PHONY: all swagger build run clean docker docker-push test dashboard-token deploy undeploy k8s-apply

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

# Сборка Docker-образа
# Использование: make docker VERSION=1.2.3

docker: swagger
	@echo "Сборка образа $(IMAGE)"
	docker build --build-arg VERSION=$(VERSION) -t $(IMAGE) .

# Публикация образа в Docker Hub (нужен docker login)
# Использование: make docker-push VERSION=1.2.3

docker-push: docker
	@echo "Публикация образа $(IMAGE)"
	docker push $(IMAGE)

# Применение всех Kubernetes манифестов (требуется контекст docker-desktop)
# Использование: make deploy VERSION=1.2.3
# 1. Сборка образа (docker-desktop использует общий демон -> образ виден кластеру)
# 2. Применение манифестов (namespace, db, pvc, app)
# 3. Обновление образа в Deployment
# 4. Ожидание завершения rollout

deploy: docker-push
	@if [ "$(CURRENT_CONTEXT)" != "docker-desktop" ]; then \
		echo "ОШИБКА: kubectl context должен быть 'docker-desktop' (текущий: $(CURRENT_CONTEXT))" >&2; exit 1; \
	fi
	@echo "Применение манифестов в namespace $(K8S_NAMESPACE) c образом $(IMAGE)";
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/db
	kubectl apply -f k8s/pvc.yaml
	kubectl apply -f k8s/app
	kubectl set image deployment/$(APP_NAME) $(APP_NAME)=$(IMAGE) -n $(K8S_NAMESPACE) --record || true
	kubectl rollout status deployment/$(APP_NAME) -n $(K8S_NAMESPACE) --timeout=120s
	@echo "Готово. Pods:";
	kubectl get pods -n $(K8S_NAMESPACE) -l app=$(APP_NAME)

# Удаление всех ресурсов (обратно к чистому состоянию). Удаление namespace последним.
undeploy:
	@if [ "$(CURRENT_CONTEXT)" != "docker-desktop" ]; then \
		echo "ОШИБКА: kubectl context должен быть 'docker-desktop' (текущий: $(CURRENT_CONTEXT))" >&2; exit 1; \
	fi
	@echo "Удаление ресурсов в namespace $(K8S_NAMESPACE)";
	- kubectl delete -f k8s/app -n $(K8S_NAMESPACE) --ignore-not-found
	- kubectl delete -f k8s/db -n $(K8S_NAMESPACE) --ignore-not-found
	- kubectl delete -f k8s/pvc.yaml -n $(K8S_NAMESPACE) --ignore-not-found
	@echo "Удаление namespace (это удалит оставшиеся ресурсы)...";
	- kubectl delete -f k8s/namespace.yaml --ignore-not-found
	@echo "Undeploy завершён."

# Генерация (или повторное использование) долгоживущего токена для Kubernetes Dashboard (ServiceAccount в kube-system)
# Использование: make dashboard-token
# Выводит токен в stdout.
# Требуется текущий kubectl context = docker-desktop.

dashboard-token:
	@chmod +x scripts/gen-dashboard-token.sh
	@./scripts/gen-dashboard-token.sh
