package api

// swagger:response helloResponse
// Represents greeting message.
type helloResponse struct {
	// in: body
	Body struct {
		Message string `json:"message"`
	} `json:"body"`
}

// swagger:response envResponse
// Represents environment variable output.
type envResponse struct {
	// in: body
	Body struct {
		ConfigMapEnvVar string `json:"configMapEnvVar"`
	} `json:"body"`
}

// swagger:response healthzResponse
// Health status.
type healthzResponse struct {
	// in: body
	Body struct {
		Status string `json:"status"`
	} `json:"body"`
}

// swagger:response readinessResponse
// Readiness status.
type readinessResponse struct {
	// in: body
	Body struct {
		Ready string `json:"ready"`
	} `json:"body"`
}

// swagger:response versionResponse
// Service version.
type versionResponse struct {
	// in: body
	Body struct {
		Version string `json:"version"`
	} `json:"body"`
}

// swagger:response secretResponse
// Secret (masked) values.
type secretResponse struct {
	// in: body
	Body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	} `json:"body"`
}

// dummy usage to silence linters about unused types (they are used by swagger annotations)
var _ = []any{
	(*helloResponse)(nil),
	(*envResponse)(nil),
	(*healthzResponse)(nil),
	(*readinessResponse)(nil),
	(*versionResponse)(nil),
	(*secretResponse)(nil),
}
