package cache

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
)

type Manager struct {
	client *redis.Client
	ctx    context.Context
}

func NewManager() (*Manager, error) {
	host := os.Getenv("REDIS_HOST")
	if host == "" {
		host = "redis:6379"
	}
	password := os.Getenv("REDIS_PASSWORD")

	client := redis.NewClient(&redis.Options{
		Addr:     host,
		Password: password,
		DB:       0,
	})

	ctx := context.Background()
	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping: %w", err)
	}

	return &Manager{client: client, ctx: ctx}, nil
}

func (m *Manager) Get(key string) (string, error) {
	val, err := m.client.Get(m.ctx, key).Result()
	if err == redis.Nil {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("redis get %q: %w", key, err)
	}
	return val, nil
}

func (m *Manager) Set(key, value string, ttl time.Duration) error {
	if err := m.client.Set(m.ctx, key, value, ttl).Err(); err != nil {
		return fmt.Errorf("redis set %q: %w", key, err)
	}
	return nil
}

func (m *Manager) Exists(key string) (bool, error) {
	n, err := m.client.Exists(m.ctx, key).Result()
	if err != nil {
		return false, fmt.Errorf("redis exists %q: %w", key, err)
	}
	return n > 0, nil
}

func (m *Manager) Close() error {
	return m.client.Close()
}
