# Миграции через golang-migrate
FROM alpine:3.23

ARG MIGRATE_VERSION=v4.17.0

# Архитектура определяется внутри образа, а не через ARG TARGETARCH: сборка идёт
# классическим билдером (DOCKER_BUILDKIT=0), который TARGETARCH не подставляет,
# а minikube на Apple Silicon — arm64, и amd64-бинарь там не запустится.
RUN apk add --no-cache curl ca-certificates bash && \
    case "$(apk --print-arch)" in \
      x86_64)  MARCH=amd64 ;; \
      aarch64) MARCH=arm64 ;; \
      *)       echo "неподдерживаемая архитектура: $(apk --print-arch)" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/golang-migrate/migrate/releases/download/${MIGRATE_VERSION}/migrate.linux-${MARCH}.tar.gz" -o /tmp/migrate.tgz && \
    tar -xzf /tmp/migrate.tgz -C /usr/local/bin migrate && \
    chmod +x /usr/local/bin/migrate && \
    rm /tmp/migrate.tgz

WORKDIR /app
COPY migrations /migrations
COPY scripts/migrations-entrypoint.sh /usr/local/bin/migrations-entrypoint.sh
RUN chmod +x /usr/local/bin/migrations-entrypoint.sh

ENV APP_POSTGRES_PORT=5432
ENTRYPOINT ["/usr/local/bin/migrations-entrypoint.sh"]
