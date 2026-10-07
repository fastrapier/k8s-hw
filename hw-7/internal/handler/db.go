package handler

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strconv"
	"time"
)

const (
	defaultListLimit = 25
	maxListLimit     = 200
	defaultReportRow = 100
	maxReportRows    = 1000
)

// swagger:route POST /db/requests db insertRequest
// Creates db record with request timestamp.
// responses:
//
//	200: dbInsertResponse
func InsertRequest(w http.ResponseWriter, r *http.Request) {
	if pgClient == nil {
		dbUnavailable(w)
		return
	}
	id, ts, err := pgClient.InsertRequest(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"id":        id,
		"createdAt": ts,
		"pod":       podName,
	})
}

// swagger:route GET /db/requests db listRequests
// Returns last N rows of the requests table.
// responses:
//
//	200: dbListResponse
func ListRequests(w http.ResponseWriter, r *http.Request) {
	if pgClient == nil {
		dbUnavailable(w)
		return
	}
	limit := intParam(r, "limit", defaultListLimit, 1, maxListLimit)
	rows, err := pgClient.ListRequests(r.Context(), limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"count": len(rows),
		"items": rows,
		"pod":   podName,
	})
}

// swagger:route GET /db/stats db dbStats
// Returns aggregates over the requests table.
// responses:
//
//	200: dbStatsResponse
func DBStats(w http.ResponseWriter, r *http.Request) {
	if pgClient == nil {
		dbUnavailable(w)
		return
	}
	stats, err := pgClient.RequestStats(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"stats": stats,
		"pod":   podName,
	})
}

// Хеширование здесь не бизнес-логика, а способ переложить нагрузку с Postgres на CPU
// пода API: HPA масштабирует по CPU именно API, а чистые SELECT-ы грузят БД.
//
// swagger:route GET /db/report db dbReport
// Returns a checksum over N rows: SQL query plus CPU-bound hashing.
// responses:
//
//	200: dbReportResponse
func DBReport(w http.ResponseWriter, r *http.Request) {
	if pgClient == nil {
		dbUnavailable(w)
		return
	}
	rowsWanted := intParam(r, "rows", defaultReportRow, 1, maxReportRows)
	started := time.Now()

	rows, err := pgClient.ListRequests(r.Context(), rowsWanted)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	digest := make([]byte, 0, sha256.Size)
	for _, row := range rows {
		digest = append(digest, []byte(strconv.FormatInt(row.ID, 10))...)
		digest = append(digest, []byte(row.CreatedAt.Format(time.RFC3339Nano))...)
	}
	sum := sha256.Sum256(digest)
	for i := 0; i < reportRounds; i++ {
		sum = sha256.Sum256(sum[:])
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"rows":      len(rows),
		"rounds":    reportRounds,
		"checksum":  hex.EncodeToString(sum[:]),
		"elapsedMs": time.Since(started).Milliseconds(),
		"pod":       podName,
		"generated": time.Now().UTC(),
	})
}

func intParam(r *http.Request, name string, def, min, max int) int {
	raw := r.URL.Query().Get(name)
	if raw == "" {
		return def
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return def
	}
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

func dbUnavailable(w http.ResponseWriter) {
	writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "db client not initialized"})
}
