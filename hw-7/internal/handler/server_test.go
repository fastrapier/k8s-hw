package handler_test

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"hw-7/internal/api"
	"hw-7/internal/config"
	"hw-7/internal/handler"
)

func testConfig() config.Config {
	return config.Config{Port: "8080", ReadinessWarmupSeconds: 1, ShutdownTimeoutSeconds: 5, ConfigMapEnvVar: "test"}
}

func performRequest(t *testing.T, mux *http.ServeMux, method, path string) *httptest.ResponseRecorder {
	req, err := http.NewRequest(method, path, nil)
	if err != nil {
		t.Fatalf("failed to build request: %v", err)
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func TestHealthz(t *testing.T) {
	mux := api.NewMux(testConfig())
	rec := performRequest(t, mux, http.MethodGet, "/healthz")
	if rec.Code != http.StatusOK {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 200, got %d body=%s", rec.Code, string(b))
	}
}

func TestReadyz(t *testing.T) {
	cfg := testConfig()
	cfg.ReadinessWarmupSeconds = 2
	mux := api.NewMux(cfg)
	handler.SetStartTime(time.Now()) // just started, should be warming
	if rec := performRequest(t, mux, http.MethodGet, "/readyz"); rec.Code != http.StatusServiceUnavailable {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 503 warming, got %d body=%s", rec.Code, string(b))
	}
	// simulate pass of time
	handler.SetStartTime(time.Now().Add(-3 * time.Second))
	if rec := performRequest(t, mux, http.MethodGet, "/readyz"); rec.Code != http.StatusOK {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 200 ready, got %d body=%s", rec.Code, string(b))
	}
}

func TestVersion(t *testing.T) {
	mux := api.NewMux(testConfig())
	rec := performRequest(t, mux, http.MethodGet, "/version")
	if rec.Code != http.StatusOK {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 200, got %d body=%s", rec.Code, string(b))
	}
	if rec.Body.Len() == 0 {
		t.Fatalf("empty body for /version")
	}
}

func TestSwaggerJSON(t *testing.T) {
	mux := api.NewMux(testConfig())
	rec := performRequest(t, mux, http.MethodGet, "/swagger.json")
	if rec.Code != http.StatusOK {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 200, got %d body=%s", rec.Code, string(b))
	}
	if rec.Body.Len() == 0 {
		t.Fatalf("swagger json empty")
	}
}

func TestSecret(t *testing.T) {
	cfg := testConfig()
	cfg.SecretUsername = "developer"
	cfg.SecretPassword = "password"
	mux := api.NewMux(cfg)
	rec := performRequest(t, mux, http.MethodGet, "/secret")
	if rec.Code != http.StatusOK {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 200, got %d body=%s", rec.Code, string(b))
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}
	if body["username"] != "developer" {
		t.Fatalf("unexpected username: %+v", body)
	}
	if body["password"] != "p***d" { // mask logic: first + *** + last
		t.Fatalf("unexpected password mask: %s", body["password"])
	}
}

// Без сконфигурированного Postgres DB-эндпоинты обязаны отдавать 503, а не паниковать:
// именно так ведёт себя под до готовности БД, и Locust не должен видеть 500.
func TestDBEndpointsWithoutDB(t *testing.T) {
	mux := api.NewMux(testConfig())
	for _, path := range []string{"/db/requests", "/db/stats", "/db/report?rows=10"} {
		rec := performRequest(t, mux, http.MethodGet, path)
		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("%s: expected 503, got %d", path, rec.Code)
		}
	}
	if rec := performRequest(t, mux, http.MethodPost, "/db/requests"); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("POST /db/requests: expected 503, got %d", rec.Code)
	}
}

func TestHello(t *testing.T) {
	mux := api.NewMux(testConfig())
	rec := performRequest(t, mux, http.MethodGet, "/")
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestPodNameHeader(t *testing.T) {
	cfg := testConfig()
	cfg.PodName = "api-hw7-abcde"
	mux := api.NewMux(cfg)
	rec := performRequest(t, mux, http.MethodGet, "/healthz")
	if got := rec.Header().Get("X-Pod-Name"); got != "api-hw7-abcde" {
		t.Fatalf("unexpected X-Pod-Name: %q", got)
	}
	if handler.PodName() != "api-hw7-abcde" {
		t.Fatalf("unexpected handler.PodName(): %q", handler.PodName())
	}
}
