package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"k8s-hw/internal/config"
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
	mux := NewMux(testConfig())
	rec := performRequest(t, mux, http.MethodGet, "/healthz")
	if rec.Code != http.StatusOK {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 200, got %d body=%s", rec.Code, string(b))
	}
}

func TestReadyz(t *testing.T) {
	cfg := testConfig()
	cfg.ReadinessWarmupSeconds = 2
	mux := NewMux(cfg)
	SetStartTime(time.Now()) // just started, should be warming
	if rec := performRequest(t, mux, http.MethodGet, "/readyz"); rec.Code != http.StatusServiceUnavailable {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 503 warming, got %d body=%s", rec.Code, string(b))
	}
	// simulate pass of time
	SetStartTime(time.Now().Add(-3 * time.Second))
	if rec := performRequest(t, mux, http.MethodGet, "/readyz"); rec.Code != http.StatusOK {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 200 ready, got %d body=%s", rec.Code, string(b))
	}
}

func TestVersion(t *testing.T) {
	mux := NewMux(testConfig())
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
	mux := NewMux(testConfig())
	rec := performRequest(t, mux, http.MethodGet, "/swagger.json")
	if rec.Code != http.StatusOK {
		b, _ := io.ReadAll(rec.Body)
		t.Fatalf("expected 200, got %d body=%s", rec.Code, string(b))
	}
	if rec.Body.Len() == 0 {
		t.Fatalf("swagger json empty")
	}
}
