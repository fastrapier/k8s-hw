# HTTP API приложения
FROM golang:1.26-alpine AS builder

ARG VERSION=latest
ENV CGO_ENABLED=0
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go build -ldflags "-s -w -X hw-9/internal/handler.Version=${VERSION}" -o /out/app .

FROM alpine:3.23
ARG VERSION=latest
RUN adduser -D -u 10001 appuser
WORKDIR /app
COPY --from=builder /out/app ./app
LABEL org.opencontainers.image.title="hw-9" \
      org.opencontainers.image.version="${VERSION}"
EXPOSE 8080
USER appuser
ENTRYPOINT ["./app"]
