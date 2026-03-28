package handler

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// swagger:route POST /pvc-test pvcTest pvcTest
// Creates a test file inside the mounted PVC data directory.
// responses:
//
//	201: pvcTestResponse
func PvcTest(w http.ResponseWriter, r *http.Request) {
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
