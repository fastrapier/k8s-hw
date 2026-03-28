FROM golang:1.26-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN CGO_ENABLED=0 go build -o /producer ./cmd/producer

FROM alpine:3.23
RUN apk add --no-cache ca-certificates
COPY --from=builder /producer /usr/local/bin/producer
ENTRYPOINT ["producer"]
