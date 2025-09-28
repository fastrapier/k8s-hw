package handler

import (
	"fmt"
	"net/http"
	"runtime"
)

// swagger:route GET / hello hello
// Returns greeting message.
// responses:
//
//	200: helloResponse
func HelloHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"message": fmt.Sprintf("Hi there! RequestURI is %s", r.RequestURI),
	})
}

// swagger:route GET /version version version
// Returns service version & go runtime.
// responses:
//
//	200: versionResponse
func VersionHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"version": Version,
		"go":      runtime.Version(),
	})
}
