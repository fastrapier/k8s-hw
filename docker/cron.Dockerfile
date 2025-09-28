# docker/cron.Dockerfile
# Образ для CronJob: периодически пишет запись в cron_runs
FROM golang:1.24-alpine AS builder
ARG VERSION=latest
ENV CGO_ENABLED=0
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -ldflags "-s -w" -o /out/cron ./cmd/cronjob

FROM alpine:3.20
RUN adduser -D -u 10002 cronuser
WORKDIR /app
COPY --from=builder /out/cron ./cron
USER cronuser
ENTRYPOINT ["./cron"]

