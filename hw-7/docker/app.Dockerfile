FROM golang:1.26-alpine AS builder

ARG VERSION=latest
ENV CGO_ENABLED=0
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Swagger-спека лежит в docs/swagger.json и вшивается через go:embed,
# поэтому генератор в образе не нужен (обновляется локально: swagger generate spec).
RUN go build -ldflags "-s -w -X hw-7/internal/handler.Version=${VERSION}" -o /out/app .

FROM alpine:3.23
ARG VERSION=latest
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 appuser
WORKDIR /app
COPY --from=builder /out/app ./app
LABEL org.opencontainers.image.title="hw-7" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/fastrapier/k8s-hw"
EXPOSE 8080
USER appuser
ENTRYPOINT ["./app"]
