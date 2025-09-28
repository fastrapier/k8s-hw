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

	"k8s-hw/internal/api"
	"k8s-hw/internal/config"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config load error: %v", err)
	}

	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Printf("Starting server on %s warmup=%s shutdownTimeout=%s", addr, cfg.ReadinessWarmup(), cfg.ShutdownTimeout())

	mux := api.NewMux(cfg)
	srv := &http.Server{Addr: addr, Handler: mux}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM, syscall.SIGINT)
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
	case <-ctx.Done():
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
}
