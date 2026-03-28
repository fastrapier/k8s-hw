package api

import (
	"net/http"

	"k8s-hw/docs"
	"k8s-hw/internal/config"
	"k8s-hw/internal/handler"
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
	mux.HandleFunc("/pvc-test", handler.PvcTest)
	mux.HandleFunc("/db/requests", handler.InsertRequest)
	return mux
}
