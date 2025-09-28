# --- Build stage ---
FROM golang:1.24-alpine AS builder

ARG VERSION=latest
ARG SWAGGER_VERSION=v0.32.3
ENV CGO_ENABLED=0
WORKDIR /src

# Кэш зависимостей
COPY go.mod go.sum ./
RUN go mod download

# Установка swagger
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go install github.com/go-swagger/go-swagger/cmd/swagger@${SWAGGER_VERSION}

# Копируем исходники
COPY . .

# Генерация swagger спецификации
RUN /go/bin/swagger generate spec -o docs/swagger.json --scan-models

# Сборка бинаря (обновлён путь переменной Version)
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -ldflags "-s -w -X k8s-hw/internal/handler.Version=${VERSION}" -o /out/app .

# --- Runtime stage ---
FROM alpine:3.20
ARG VERSION=latest

RUN adduser -D -u 10001 appuser
WORKDIR /app
COPY --from=builder /out/app ./app

LABEL org.opencontainers.image.title="k8s-hw" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://example.local/k8s-hw"

EXPOSE 8080
USER appuser
ENTRYPOINT ["./app"]
