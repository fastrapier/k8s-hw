package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"hw-4/internal/cache"
	"hw-4/internal/rabbitmq"
	"hw-4/internal/tasks"
	"hw-4/internal/vault"
)

const exchangeName = "api_tasks"

type Message struct {
	API    string            `json:"api"`
	Params map[string]string `json:"params"`
}

func main() {
	queue := flag.String("queue", "", "queue to consume: weather or news")
	rmqHost := flag.String("rmq-host", "rabbitmq.local", "RabbitMQ host")
	flag.Parse()

	if *queue == "" {
		fmt.Fprintln(os.Stderr, "usage: consumer --queue <weather|news>")
		os.Exit(1)
	}
	if *queue != "weather" && *queue != "news" {
		log.Fatalf("unknown queue %q, expected weather or news", *queue)
	}

	vc, err := vault.NewClient()
	if err != nil {
		log.Fatalf("vault: %v", err)
	}

	// Redis CacheManager (получает пароль из Vault)
	redisPass, err := vc.GetSecret("secret/redis", "password")
	if err != nil {
		log.Printf("[WARN] vault get redis password: %v (caching disabled)", err)
	}
	if redisPass != "" {
		os.Setenv("REDIS_PASSWORD", redisPass)
	}

	cm, err := cache.NewManager()
	if err != nil {
		log.Printf("[WARN] redis: %v (caching disabled)", err)
		cm = nil
	} else {
		defer cm.Close()
		fmt.Println("[OK] Redis connected, caching enabled")
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

	if _, err := conn.DeclareAndBindQueue(*queue, exchangeName, *queue); err != nil {
		log.Fatalf("declare/bind queue: %v", err)
	}

	msgs, err := conn.Channel.Consume(
		*queue,
		"",
		false, // manual ack
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		log.Fatalf("consume: %v", err)
	}

	fmt.Printf("[*] Waiting for messages on queue=%s. Press Ctrl+C to exit.\n", *queue)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)

	for {
		select {
		case <-sig:
			fmt.Println("\n[*] Shutting down")
			return
		case d, ok := <-msgs:
			if !ok {
				log.Println("channel closed, exiting")
				return
			}
			handleMessage(vc, cm, d.Body)
			if err := d.Ack(false); err != nil {
				log.Printf("ack: %v", err)
			}
		}
	}
}

func handleMessage(vc *vault.Client, cm *cache.Manager, body []byte) {
	var msg Message
	if err := json.Unmarshal(body, &msg); err != nil {
		log.Printf("unmarshal message: %v", err)
		return
	}
	fmt.Printf("[>] Received: api=%s params=%v\n", msg.API, msg.Params)

	switch msg.API {
	case "weather":
		apiKey, err := vc.GetSecret("secret/weather", "api_key")
		if err != nil {
			log.Printf("vault get weather api_key: %v", err)
			return
		}
		city := msg.Params["city"]
		if city == "" {
			city = "Moscow"
		}
		if err := tasks.FetchWeather(apiKey, city, cm); err != nil {
			log.Printf("fetch weather: %v", err)
		}

	case "news":
		apiKey, err := vc.GetSecret("secret/news", "api_key")
		if err != nil {
			log.Printf("vault get news api_key: %v", err)
			return
		}
		query := msg.Params["q"]
		if query == "" {
			query = "technology"
		}
		if err := tasks.FetchNews(apiKey, query, cm); err != nil {
			log.Printf("fetch news: %v", err)
		}

	default:
		log.Printf("unknown api: %s", msg.API)
	}
}
