package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"k8s-hw/internal/config"
)

// Version задаётся через -ldflags "-X k8s-hw/internal/api.Version=..."
var Version = "latest"

var (
	startTime      = time.Now()
	warmupDur      = time.Second
	configMapVal   string
	secretUsername string
	secretPassword string
	dataDir        string
	podName        string
)

// InitConfig инициализирует внутренние параметры из config.Config
func InitConfig(cfg config.Config) {
	warmupDur = cfg.ReadinessWarmup()
	configMapVal = cfg.ConfigMapEnvVar
	secretUsername = cfg.SecretUsername
	secretPassword = cfg.SecretPassword
	dataDir = cfg.DataDir
	podName = cfg.PodName
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

// swagger:route GET /test-env config-map testEnv
// Returns value configured via CONFIG_MAP_ENV_VAR.
// responses:
//
//	200: envResponse
func testEnv(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"configMapEnvVar": configMapVal,
	})
}

// swagger:route GET /healthz healthcheck healthz
// Liveness/health check.
// responses:
//
//	200: healthzResponse
func healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// swagger:route GET /readyz healthcheck readyz
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

// swagger:route GET /secret secret secret
// Returns (masked) secret values injected via environment.
// responses:
//
//	200: secretResponse
func secret(w http.ResponseWriter, _ *http.Request) {
	masked := ""
	if len(secretPassword) > 0 {
		if len(secretPassword) <= 3 {
			masked = "***"
		} else {
			masked = secretPassword[:1] + "***" + secretPassword[len(secretPassword)-1:]
		}
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"username": secretUsername,
		"password": masked,
	})
}

// swagger:route POST /pvc-test pvcTest pvcTest
// Creates a test file inside the mounted PVC data directory.
// responses:
//
//	201: pvcTestResponse
func pvcTest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	if dataDir == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "dataDir not configured"})
		return
	}
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": fmt.Sprintf("mkdir: %v", err)})
		return
	}

	name := fmt.Sprintf("%s-%d.txt", podName, time.Now().UnixNano())
	fullPath := filepath.Join(dataDir, podName)
	content := fmt.Sprintf("pod=%s created at %s\n", podName, time.Now().Format(time.RFC3339Nano))
	if err := os.WriteFile(fullPath, []byte(content), 0o644); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": fmt.Sprintf("write: %v", err)})
		return
	}
	info, err := os.Stat(fullPath)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": fmt.Sprintf("stat: %v", err)})
		return
	}
	w.WriteHeader(http.StatusCreated)
	writeJSON(w, http.StatusCreated, map[string]any{
		"file":      name,
		"path":      fullPath,
		"sizeBytes": info.Size(),
		"podName":   podName,
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
	mux.HandleFunc("/secret", secret)
	mux.HandleFunc("/swagger.json", swaggerJSON)
	mux.HandleFunc("/swagger", swaggerUI)
	mux.HandleFunc("/swagger/", swaggerUI)
	mux.HandleFunc("/pvc-test", pvcTest)
	return mux
}
