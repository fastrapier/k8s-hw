package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"runtime"
	"time"

	"k8s-hw/internal/config"
)

// Version задаётся через -ldflags "-X k8s-hw/internal/api.Version=..."
var Version = "dev"

var (
	startTime    = time.Now()
	warmupDur    = time.Second
	configMapVal string
)

// InitConfig инициализирует внутренние параметры из config.Config
func InitConfig(cfg config.Config) {
	warmupDur = cfg.ReadinessWarmup()
	configMapVal = cfg.ConfigMapEnvVar
	startTime = time.Now()
}

// SetStartTime позволяет тестам переопределять момент запуска для проверки /readyz
func SetStartTime(t time.Time) { startTime = t }

// writeJSON helper
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// swagger:route GET / hello hello
// Returns greeting message.
// responses:
//
//	200: helloResponse
func hello(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"message": fmt.Sprintf("Hi there! RequestURI is %s", r.RequestURI),
	})
}

// swagger:route GET /test-env testEnv testEnv
// Returns value configured via CONFIG_MAP_ENV_VAR.
// responses:
//
//	200: envResponse
func testEnv(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"configMapEnvVar": configMapVal,
	})
}

// swagger:route GET /healthz healthz healthz
// Liveness/health check.
// responses:
//
//	200: healthzResponse
func healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// swagger:route GET /readyz readiness readiness
// Readiness check.
// responses:
//
//	200: readinessResponse
func readyz(w http.ResponseWriter, _ *http.Request) {
	if time.Since(startTime) < warmupDur {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"ready": "warming"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"ready": "true"})
}

// swagger:route GET /version version version
// Returns service version & go runtime.
// responses:
//
//	200: versionResponse
func version(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"version": Version,
		"go":      runtime.Version(),
	})
}

// NewMux возвращает готовый роутер с инициализированной конфигурацией
func NewMux(cfg config.Config) *http.ServeMux {
	InitConfig(cfg)
	mux := http.NewServeMux()
	mux.HandleFunc("/", hello)
	mux.HandleFunc("/test-env", testEnv)
	mux.HandleFunc("/healthz", healthz)
	mux.HandleFunc("/readyz", readyz)
	mux.HandleFunc("/version", version)
	mux.HandleFunc("/swagger.json", swaggerJSON)
	mux.HandleFunc("/swagger", swaggerUI)
	mux.HandleFunc("/swagger/", swaggerUI)
	return mux
}
