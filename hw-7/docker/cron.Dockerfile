FROM golang:1.26-alpine AS builder

ENV CGO_ENABLED=0
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -ldflags "-s -w" -o /out/cron ./cmd/cronjob

FROM alpine:3.23
RUN apk add --no-cache ca-certificates && adduser -D -u 10002 cronuser
WORKDIR /app
COPY --from=builder /out/cron ./cron
USER cronuser
ENTRYPOINT ["./cron"]
