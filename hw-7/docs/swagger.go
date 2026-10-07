package docs

import (
	"net/http"
)

// SwaggerJSON Returns swagger spec.
func SwaggerJSON(w http.ResponseWriter, _ *http.Request) {
	if len(swaggerSpec) == 0 {
		http.Error(w, "swagger spec not embedded", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write(swaggerSpec)
}

// SwaggerUI Returns swagger UI HTML page.
func SwaggerUI(w http.ResponseWriter, _ *http.Request) {
	html := `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Swagger UI</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
<style>body{margin:0;padding:0;}#swagger-ui{box-sizing:border-box;}</style></head>
<body><div id="swagger-ui"></div><script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
<script>window.onload=function(){SwaggerUIBundle({url:'/swagger.json',dom_id:'#swagger-ui',layout:'BaseLayout'});};</script></body></html>`
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(html))
}
