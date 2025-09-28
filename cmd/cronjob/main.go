package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"k8s-hw/internal/config"
	"k8s-hw/internal/db"
)

// Простой cron: однократный запуск, вставляет запись в cron_runs.
func main() {
	log.Println("cronjob start")
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	pg := cfg.Postgres
	if pg.Host == "" || pg.User == "" || pg.DB == "" {
		log.Fatalf("postgres config incomplete (need APP_POSTGRES_HOST/USER/DB)")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// handle signals
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		select {
		case s := <-sigCh:
			log.Printf("signal %s, cancelling", s)
			cancel()
		case <-ctx.Done():
		}
	}()

	// simple retry for DB connect
	var client *db.Client
	for attempt := 1; attempt <= 10; attempt++ {
		cctx, ccancel := context.WithTimeout(ctx, 5*time.Second)
		client, err = db.New(cctx, pg)
		ccancel()
		if err == nil {
			break
		}
		log.Printf("db connect attempt %d failed: %v", attempt, err)
		time.Sleep(time.Second * 2)
	}
	if err != nil || client == nil {
		log.Fatalf("cannot connect db: %v", err)
	}
	defer client.Close()

	id, ts, err := client.InsertCronRun(ctx)
	if err != nil {
		log.Fatalf("insert cron run: %v", err)
	}
	log.Printf("cron run inserted id=%d executed_at=%s", id, ts.Format(time.RFC3339Nano))
	fmt.Println("OK")
}
