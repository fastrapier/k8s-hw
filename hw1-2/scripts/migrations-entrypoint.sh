#!/bin/sh
set -eu

# Проверяем обязательные переменные
: "${APP_POSTGRES_HOST:?need APP_POSTGRES_HOST}"
: "${APP_POSTGRES_PORT:?need APP_POSTGRES_PORT}"
: "${APP_POSTGRES_DB:?need APP_POSTGRES_DB}"
: "${APP_POSTGRES_USER:?need APP_POSTGRES_USER}"
: "${APP_POSTGRES_PASSWORD:?need APP_POSTGRES_PASSWORD}"

DB_URL="postgres://${APP_POSTGRES_USER}:${APP_POSTGRES_PASSWORD}@${APP_POSTGRES_HOST}:${APP_POSTGRES_PORT}/${APP_POSTGRES_DB}?sslmode=disable"

echo "[migrate] applying migrations: $DB_URL"
exec /usr/local/bin/migrate -path /migrations -database "$DB_URL" up

