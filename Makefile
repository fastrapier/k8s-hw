APP_NAME = k8s-test-backend-app
VERSION ?= latest
SWAGGER_JSON = internal/api/swagger.json
SWAGGER_BIN = $(shell go env GOPATH)/bin/swagger
LDFLAGS = -X k8s-hw/internal/api.Version=$(VERSION)

.PHONY: all swagger build run clean docker test dashboard-token

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

# Build docker image
# Usage: make docker VERSION=1.2.3

docker:
	docker build --build-arg VERSION=$(VERSION) -t $(APP_NAME):$(VERSION) .

# Generate (or reuse) long-lived dashboard login token (ServiceAccount in kube-system)
# Usage: make dashboard-token
# Prints token to stdout.
# Требует текущий kubectl context = docker-desktop.

dashboard-token:
	@chmod +x scripts/gen-dashboard-token.sh
	@./scripts/gen-dashboard-token.sh
