package handler

import "net/http"

// swagger:route GET /secret secret secret
// Returns (masked) secret values injected via environment.
// responses:
//
//	200: secretResponse
func Secret(w http.ResponseWriter, _ *http.Request) {
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

// swagger:route GET /test-env config-map testEnv
// Returns value configured via CONFIG_MAP_ENV_VAR.
// responses:
//
//	200: envResponse
func TestEnv(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"configMapEnvVar": configMapVal,
	})
}
