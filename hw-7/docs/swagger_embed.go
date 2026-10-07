package docs

import (
	_ "embed"
	"log"
	"os"
)

//go:embed swagger.json
var swaggerSpec []byte

func init() {
	if len(swaggerSpec) > 0 {
		return
	}
	paths := []string{"docs/swagger.json", "swagger.json"}
	for _, p := range paths {
		if b, err := os.ReadFile(p); err == nil {
			swaggerSpec = b
			return
		}
	}
	log.Printf("swagger spec not found via embed nor filesystem fallback")
}
