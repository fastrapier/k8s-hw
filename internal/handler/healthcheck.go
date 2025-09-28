package handler

import (
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
// Readiness check.
// responses:
//
//	200: readinessResponse
func Readyz(w http.ResponseWriter, _ *http.Request) {
	if time.Since(startTime) < warmupDur {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"ready": "warming"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"ready": "true"})
}
