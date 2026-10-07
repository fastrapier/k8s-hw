package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"time"
)

// Значения подставляются линкером при сборке образа:
// -ldflags "-X main.version=... -X main.commit=..."
var (
	version = "dev"
	commit  = "none"
)

type versionInfo struct {
	Version string `json:"version"`
	Commit  string `json:"commit"`
	EnvTag  string `json:"env_version"`
}

func main() {
	addr := ":" + envOr("PORT", "8080")

	log.Printf("hw-8 app starting: version=%s commit=%s addr=%s", version, commit, addr)
	log.Printf("APP_VERSION from env: %s", envOr("APP_VERSION", "<unset>"))

	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("GET /version", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, versionInfo{
			Version: version,
			Commit:  commit,
			EnvTag:  envOr("APP_VERSION", ""),
		})
	})

	mux.HandleFunc("GET /", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte("hw-8 CI/CD demo — version " + version + " (" + commit + ")\n"))
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server failed: %v", err)
	}
}

func writeJSON(w http.ResponseWriter, payload any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(payload)
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
