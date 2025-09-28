package db

import (
	"context"
	"fmt"
	"time"

	"k8s-hw/internal/config"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Client обёртка над пулом соединений.
type Client struct {
	pool *pgxpool.Pool
}

// New создаёт пул подключений к Postgres на основе конфигурации.
// Требуются поля: Host, Port, User, Pass, DB.
func New(ctx context.Context, pc config.Postgres) (*Client, error) {
	if pc.Host == "" || pc.User == "" || pc.DB == "" {
		return nil, fmt.Errorf("postgres config incomplete (host/user/db required)")
	}
	// password может быть пустой (например, trust auth в dev)
	connStr := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=disable pool_max_conns=5", pc.Host, pc.Port, pc.User, pc.Pass, pc.DB)
	cfg, err := pgxpool.ParseConfig(connStr)
	if err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	cfg.MaxConnIdleTime = 2 * time.Minute
	cfg.MaxConnLifetime = 30 * time.Minute
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("create pool: %w", err)
	}
	c := &Client{pool: pool}
	if err := c.init(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return c, nil
}

// init выполняет создание необходимых таблиц.
func (c *Client) init(ctx context.Context) error {
	_, err := c.pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS requests(
		id BIGSERIAL PRIMARY KEY,
		created_at TIMESTAMPTZ NOT NULL DEFAULT now()
	)`)
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	return nil
}

// InsertRequest вставляет новую запись и возвращает id и timestamp.
func (c *Client) InsertRequest(ctx context.Context) (id int64, createdAt time.Time, err error) {
	row := c.pool.QueryRow(ctx, "INSERT INTO requests DEFAULT VALUES RETURNING id, created_at")
	if err = row.Scan(&id, &createdAt); err != nil {
		return 0, time.Time{}, err
	}
	return
}

// Ping проверяет доступность БД.
func (c *Client) Ping(ctx context.Context) error { return c.pool.Ping(ctx) }

// Close закрывает пул.
func (c *Client) Close() { c.pool.Close() }
