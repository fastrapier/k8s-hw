package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"hw-4/internal/rabbitmq"
	"hw-4/internal/vault"
)

const exchangeName = "api_tasks"

type Message struct {
	API    string            `json:"api"`
	Params map[string]string `json:"params"`
}

func main() {
	api := flag.String("api", "", "task type: weather or news")
	params := flag.String("params", "", "query params, e.g. city=Moscow or q=kubernetes")
	rmqHost := flag.String("rmq-host", "rabbitmq.local", "RabbitMQ host")
	flag.Parse()

	if *api == "" {
		fmt.Fprintln(os.Stderr, "usage: producer --api <weather|news> --params <key=value>")
		os.Exit(1)
	}
	if *api != "weather" && *api != "news" {
		log.Fatalf("unknown api %q, expected weather or news", *api)
	}

	parsedParams := parseParams(*params)

	vc, err := vault.NewClient()
	if err != nil {
		log.Fatalf("vault: %v", err)
	}

	username, err := vc.GetSecret("secret/rabbitmq", "username")
	if err != nil {
		log.Fatalf("vault get rabbitmq username: %v", err)
	}
	password, err := vc.GetSecret("secret/rabbitmq", "password")
	if err != nil {
		log.Fatalf("vault get rabbitmq password: %v", err)
	}

	conn, err := rabbitmq.Dial(*rmqHost, username, password)
	if err != nil {
		log.Fatalf("rabbitmq dial: %v", err)
	}
	defer conn.Close()

	if err := conn.DeclareExchange(exchangeName); err != nil {
		log.Fatalf("declare exchange: %v", err)
	}

	msg := Message{API: *api, Params: parsedParams}
	body, err := json.Marshal(msg)
	if err != nil {
		log.Fatalf("marshal message: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	err = conn.Channel.PublishWithContext(ctx,
		exchangeName,
		*api, // routing key
		false,
		false,
		amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  "application/json",
			Body:         body,
		},
	)
	if err != nil {
		log.Fatalf("publish: %v", err)
	}

	fmt.Printf("[OK] Published to exchange=%s routing_key=%s body=%s\n", exchangeName, *api, string(body))
}

func parseParams(raw string) map[string]string {
	result := make(map[string]string)
	if raw == "" {
		return result
	}
	for _, pair := range strings.Split(raw, ",") {
		kv := strings.SplitN(strings.TrimSpace(pair), "=", 2)
		if len(kv) == 2 {
			result[kv[0]] = kv[1]
		}
	}
	return result
}
