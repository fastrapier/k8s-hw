package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"hw-7/internal/config"
	"hw-7/internal/db"
)

// Version задаётся через -ldflags "-X hw-7/internal/handler.Version=..."
var Version = "latest"

var (
	startTime      = time.Now()
	warmupDur      = time.Second
	configMapVal   string
	secretUsername string
	secretPassword string
	podName        string
	reportRounds   = 200
	pgClient       *db.Client
	postgresCfg    config.Postgres
	wantDB         bool
	dbMu           sync.Mutex
)

// InitConfig инициализирует внутренние параметры из config.Config
func InitConfig(cfg config.Config) {
	warmupDur = cfg.ReadinessWarmup()
	configMapVal = cfg.ConfigMapEnvVar
	secretUsername = cfg.SecretUsername
	secretPassword = cfg.SecretPassword
	podName = cfg.PodName
	reportRounds = cfg.ReportRounds
	postgresCfg = cfg.Postgres
	wantDB = postgresCfg.User != "" && postgresCfg.DB != "" && postgresCfg.Host != ""
	startTime = time.Now()
}

// SetDB передаёт и сохраняет клиент Postgres
func SetDB(c *db.Client) { pgClient = c }

// SetStartTime позволяет тестам переопределять момент запуска для проверки /readyz
func SetStartTime(t time.Time) { startTime = t }

// PodName возвращает имя пода, обслужившего запрос.
func PodName() string { return podName }

// ensureDB пытается (лениво) инициализировать клиент, если он требуется и ещё не создан.
func ensureDB(ctx context.Context) error {
	if !wantDB { // БД не обязательна — пропускаем
		return nil
	}
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
	w.Header().Set("X-Pod-Name", podName)
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
