FROM golang:1.26-alpine AS builder

ARG VERSION=dev
ARG COMMIT=none

WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY cmd ./cmd

RUN CGO_ENABLED=0 go build \
      -ldflags "-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
      -o /out/app ./cmd/app

FROM alpine:3.23
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
COPY --from=builder /out/app /usr/local/bin/app
USER 10001
EXPOSE 8080
ENTRYPOINT ["app"]
