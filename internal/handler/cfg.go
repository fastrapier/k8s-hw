package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"k8s-hw/internal/config"
	"k8s-hw/internal/db"
)

// Version VersionHandler задаётся через -ldflags "-X k8s-hw/internal/api.VersionHandler=..."
var Version = "latest"

var (
	startTime      = time.Now()
	warmupDur      = time.Second
	configMapVal   string
	secretUsername string
	secretPassword string
	dataDir        string
	podName        string
	pgClient       *db.Client
	postgresCfg    config.Postgres
	dbMu           sync.Mutex
)

// InitConfig инициализирует внутренние параметры из config.Config
func InitConfig(cfg config.Config) {
	warmupDur = cfg.ReadinessWarmup()
	configMapVal = cfg.ConfigMapEnvVar
	secretUsername = cfg.SecretUsername
	secretPassword = cfg.SecretPassword
	dataDir = cfg.DataDir
	podName = cfg.PodName
	postgresCfg = cfg.Postgres
	startTime = time.Now()
}

// SetDB передаёт и сохраняет клиент Postgres
func SetDB(c *db.Client) { pgClient = c }

// SetStartTime позволяет тестам переопределять момент запуска для проверки /readyz
func SetStartTime(t time.Time) { startTime = t }

// ensureDB пытается (лениво) инициализировать клиент, если он требуется и ещё не создан.
func ensureDB(ctx context.Context) error {
	if pgClient != nil { // уже есть
		return nil
	}
	dbMu.Lock()
	defer dbMu.Unlock()
	if pgClient != nil { // двойная проверка после захвата
		return nil
	}
	// короткий таймаут на попытку
	cctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	client, err := db.New(cctx, postgresCfg)
	if err != nil {
		return err
	}
	pgClient = client
	return nil
}

// writeJSON helper
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
