# Образ для запуска миграций через golang-migrate
FROM alpine:3.20
ARG MIGRATE_VERSION=v4.17.0
RUN apk add --no-cache curl ca-certificates bash && \
    curl -L https://github.com/golang-migrate/migrate/releases/download/${MIGRATE_VERSION}/migrate.linux-amd64.tar.gz -o /tmp/migrate.tgz && \
    tar -xzf /tmp/migrate.tgz -C /usr/local/bin migrate && \
    chmod +x /usr/local/bin/migrate && rm /tmp/migrate.tgz
WORKDIR /app
COPY migrations /migrations
COPY scripts/migrations-entrypoint.sh /usr/local/bin/migrations-entrypoint.sh
RUN chmod +x /usr/local/bin/migrations-entrypoint.sh
ENV APP_POSTGRES_PORT=5432
ENTRYPOINT ["/usr/local/bin/migrations-entrypoint.sh"]
