package handler

import "net/http"

// swagger:route POST /db/requests db insertRequest
// Creates db record with request timestamp.
// responses:
//
//	200: dbInsertResponse
func InsertRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if pgClient == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "db client not initialized"})
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
	})
}
