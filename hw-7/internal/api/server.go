package api

import (
	"net/http"

	"hw-7/docs"
	"hw-7/internal/config"
	"hw-7/internal/handler"
)

// NewMux возвращает готовый роутер с инициализированной конфигурацией
func NewMux(cfg config.Config) *http.ServeMux {
	handler.InitConfig(cfg)
	mux := http.NewServeMux()
	mux.HandleFunc("/", handler.HelloHandler)
	mux.HandleFunc("/test-env", handler.TestEnv)
	mux.HandleFunc("/healthz", handler.Healthz)
	mux.HandleFunc("/readyz", handler.Readyz)
	mux.HandleFunc("/version", handler.VersionHandler)
	mux.HandleFunc("/secret", handler.Secret)
	mux.HandleFunc("/swagger.json", docs.SwaggerJSON)
	mux.HandleFunc("/swagger", docs.SwaggerUI)
	mux.HandleFunc("/swagger/", docs.SwaggerUI)
	mux.HandleFunc("POST /db/requests", handler.InsertRequest)
	mux.HandleFunc("GET /db/requests", handler.ListRequests)
	mux.HandleFunc("GET /db/stats", handler.DBStats)
	mux.HandleFunc("GET /db/report", handler.DBReport)
	return mux
}
