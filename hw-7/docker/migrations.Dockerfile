FROM alpine:3.23
ARG MIGRATE_VERSION=v4.17.0
# Архитектуру берём из uname, а не из TARGETARCH: сборка идёт без BuildKit
# (werf с docker-server backend), поэтому автоматических платформенных ARG-ов нет.
RUN apk add --no-cache curl ca-certificates bash && \
    case "$(uname -m)" in \
      aarch64|arm64) ARCH=arm64 ;; \
      x86_64|amd64)  ARCH=amd64 ;; \
      *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/golang-migrate/migrate/releases/download/${MIGRATE_VERSION}/migrate.linux-${ARCH}.tar.gz" -o /tmp/migrate.tgz && \
    tar -xzf /tmp/migrate.tgz -C /usr/local/bin migrate && \
    chmod +x /usr/local/bin/migrate && rm /tmp/migrate.tgz
WORKDIR /app
COPY migrations /migrations
COPY scripts/migrations-entrypoint.sh /usr/local/bin/migrations-entrypoint.sh
RUN chmod +x /usr/local/bin/migrations-entrypoint.sh
ENV APP_POSTGRES_PORT=5432
ENTRYPOINT ["/usr/local/bin/migrations-entrypoint.sh"]
