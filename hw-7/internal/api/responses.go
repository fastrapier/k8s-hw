package api

import "time"

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

// swagger:response dbInsertResponse
// DB insert result.
type dbInsertResponse struct {
	// in: body
	Body struct {
		ID        int64     `json:"id"`
		CreatedAt time.Time `json:"createdAt"`
		Pod       string    `json:"pod"`
	} `json:"body"`
}

// swagger:response dbListResponse
// Last N rows of the requests table.
type dbListResponse struct {
	// in: body
	Body struct {
		Count int `json:"count"`
		Items []struct {
			ID        int64     `json:"id"`
			CreatedAt time.Time `json:"createdAt"`
		} `json:"items"`
		Pod string `json:"pod"`
	} `json:"body"`
}

// swagger:response dbStatsResponse
// Aggregates over the requests table.
type dbStatsResponse struct {
	// in: body
	Body struct {
		Stats struct {
			Total      int64      `json:"total"`
			First      *time.Time `json:"first"`
			Last       *time.Time `json:"last"`
			RecentHour int64      `json:"recentHour"`
		} `json:"stats"`
		Pod string `json:"pod"`
	} `json:"body"`
}

// swagger:response dbReportResponse
// Checksum report over N rows.
type dbReportResponse struct {
	// in: body
	Body struct {
		Rows      int       `json:"rows"`
		Rounds    int       `json:"rounds"`
		Checksum  string    `json:"checksum"`
		ElapsedMs int64     `json:"elapsedMs"`
		Pod       string    `json:"pod"`
		Generated time.Time `json:"generated"`
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
	(*dbInsertResponse)(nil),
	(*dbListResponse)(nil),
	(*dbStatsResponse)(nil),
	(*dbReportResponse)(nil),
}
