package handler

import (
	"context"
	"net/http"
	"time"
)

// swagger:route GET /healthz healthcheck healthz
// Liveness/health check.
// responses:
//
//	200: healthzResponse
func Healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// swagger:route GET /readyz healthcheck readyz
// Readiness check: учитывает время прогрева и готовность БД (если сконфигурирована).
// responses:
//
//	200: readinessResponse
func Readyz(w http.ResponseWriter, r *http.Request) {
	// 1. Общий прогрев
	if time.Since(startTime) < warmupDur {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"ready": "warming"})
		return
	}
	// 2. Если БД требуется — пытаемся лениво подключиться и пропинговать
	if err := ensureDB(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"ready": "db-connecting"})
		return
	}
	if pgClient != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 500*time.Millisecond)
		err := pgClient.Ping(ctx)
		cancel()
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"ready": "db-ping-fail"})
			return
		}
	}

	// 3. Всё готово
	writeJSON(w, http.StatusOK, map[string]string{"ready": "true"})
}
