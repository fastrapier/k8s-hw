package db

import (
	"context"
	"fmt"
	"time"

	"hw-7/internal/config"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Client обёртка над пулом соединений.
type Client struct {
	pool *pgxpool.Pool
}

// Request — строка таблицы requests.
type Request struct {
	ID        int64     `json:"id"`
	CreatedAt time.Time `json:"createdAt"`
}

// Stats — агрегаты по таблице requests.
type Stats struct {
	Total      int64      `json:"total"`
	First      *time.Time `json:"first"`
	Last       *time.Time `json:"last"`
	RecentHour int64      `json:"recentHour"`
}

// New создаёт пул подключений к Postgres на основе конфигурации.
func New(ctx context.Context, pc config.Postgres) (*Client, error) {
	if pc.Host == "" || pc.User == "" || pc.DB == "" {
		return nil, fmt.Errorf("postgres config incomplete (host/user/db required)")
	}
	connStr := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=disable pool_max_conns=%d",
		pc.Host, pc.Port, pc.User, pc.Pass, pc.DB, pc.MaxConns,
	)
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
	return &Client{pool: pool}, nil
}

// InsertRequest вставляет новую запись и возвращает id и timestamp.
func (c *Client) InsertRequest(ctx context.Context) (id int64, createdAt time.Time, err error) {
	row := c.pool.QueryRow(ctx, "INSERT INTO requests DEFAULT VALUES RETURNING id, created_at")
	if err = row.Scan(&id, &createdAt); err != nil {
		return 0, time.Time{}, err
	}
	return
}

// ListRequests возвращает последние limit записей.
func (c *Client) ListRequests(ctx context.Context, limit int) ([]Request, error) {
	rows, err := c.pool.Query(ctx,
		"SELECT id, created_at FROM requests ORDER BY id DESC LIMIT $1", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Request, 0, limit)
	for rows.Next() {
		var r Request
		if err := rows.Scan(&r.ID, &r.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// RequestStats считает агрегаты по таблице requests.
func (c *Client) RequestStats(ctx context.Context) (Stats, error) {
	var s Stats
	row := c.pool.QueryRow(ctx, `
		SELECT count(*),
		       min(created_at),
		       max(created_at),
		       count(*) FILTER (WHERE created_at > now() - interval '1 hour')
		FROM requests`)
	if err := row.Scan(&s.Total, &s.First, &s.Last, &s.RecentHour); err != nil {
		return Stats{}, err
	}
	return s, nil
}

// InsertCronRun вставляет запись о выполнении cron и возвращает id и executed_at.
func (c *Client) InsertCronRun(ctx context.Context) (id int64, executedAt time.Time, err error) {
	row := c.pool.QueryRow(ctx, "INSERT INTO cron_runs DEFAULT VALUES RETURNING id, executed_at")
	if err = row.Scan(&id, &executedAt); err != nil {
		return 0, time.Time{}, err
	}
	return
}

// Ping проверяет доступность БД.
func (c *Client) Ping(ctx context.Context) error { return c.pool.Ping(ctx) }

// Close закрывает пул.
func (c *Client) Close() { c.pool.Close() }
