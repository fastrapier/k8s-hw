package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"k8s-hw/internal/api"
	"k8s-hw/internal/config"
	"k8s-hw/internal/db"
	"k8s-hw/internal/handler"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config load error: %v", err)
	}
	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Printf("Starting server on %s warmup=%s shutdownTimeout=%s", addr, cfg.ReadinessWarmup(), cfg.ShutdownTimeout())

	// Init DB client (optional: only if required fields заданы)
	var pgClient *db.Client
	if cfg.Postgres.User == "" || cfg.Postgres.DB == "" { // считаем не настроенным
		log.Println("Postgres not configured (APP_POSTGRES_USER/DB empty) — DB features disabled")
	} else {
		ctx, cancelDB := context.WithTimeout(context.Background(), 10*time.Second)
		pgClient, err = db.New(ctx, cfg.Postgres)
		cancelDB()
		if err != nil {
			log.Printf("WARN: failed to init postgres (DB features disabled): %v", err)
		} else {
			handler.SetDB(pgClient)
			log.Printf("Postgres client initialized host=%s db=%s", cfg.Postgres.Host, cfg.Postgres.DB)
		}
	}

	mux := api.NewMux(cfg)
	srv := &http.Server{Addr: addr, Handler: mux}

	ctxShutdown, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		log.Println("HTTP server is listening")
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case <-ctxShutdown.Done():
		log.Println("Shutdown signal received")
	case err := <-errCh:
		if err != nil {
			log.Fatalf("Server start error: %v", err)
		}
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout())
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("Graceful shutdown failed, forcing close: %v", err)
		if cerr := srv.Close(); cerr != nil {
			log.Printf("Additional close error: %v", cerr)
		}
	} else {
		log.Println("Server stopped gracefully")
	}
	if pgClient != nil {
		pgClient.Close()
		log.Println("Postgres client closed")
	}
}
