# --- Build stage ---
FROM golang:1.24-alpine AS builder

ARG VERSION=dev
ENV CGO_ENABLED=0
WORKDIR /src

# deps caching
COPY go.mod go.sum ./
RUN go mod download

# install goswagger (pin)
RUN go install github.com/go-swagger/go-swagger/cmd/swagger@v0.32.3

# copy sources
COPY . .

# generate swagger spec inside internal/api
RUN swagger generate spec -o internal/api/swagger.json --scan-models

# build binary with version ldflags
RUN go build -ldflags "-s -w -X k8s-hw/internal/api.Version=${VERSION}" -o /out/app .

# --- Runtime stage ---
FROM alpine:3.20
ARG VERSION=dev

RUN adduser -D -u 10001 appuser
WORKDIR /app
COPY --from=builder /out/app ./app

LABEL org.opencontainers.image.title="k8s-hw" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://example.local/k8s-hw"

EXPOSE 8080
USER appuser

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s CMD wget -q -O - http://localhost:8080/healthz || exit 1

ENTRYPOINT ["./app"]
