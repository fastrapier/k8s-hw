package config

import (
	"time"

	"github.com/kelseyhightower/envconfig"
)

// Config описывает параметры запуска сервиса, загружаемые из переменных окружения (префикс APP_).
//
// Переменные:
//   APP_PORT (string)                       - порт HTTP (default 8080)
//   APP_READINESS_WARMUP_SECONDS (int)      - время (сек) для /readyz warming (default 1)
//   APP_SHUTDOWN_TIMEOUT_SECONDS (int)      - таймаут graceful shutdown (default 10)
//   APP_CONFIG_MAP_ENV_VAR (string)         - значение для /test-env (default пусто)
//   APP_SECRET_USERNAME (string)            - (из k8s Secret) имя пользователя (optional)
//   APP_SECRET_PASSWORD (string)            - (из k8s Secret) пароль (optional)
//   APP_POD_NAME (string)                   - имя пода (отдаётся в ответах, видно распределение нагрузки)
//   APP_REPORT_ROUNDS (int)                 - число раундов хеширования в /db/report (default 200)
//   APP_POSTGRES_* (см. Postgres)

type Config struct {
	Port                   string   `envconfig:"PORT" default:"8080"`
	ReadinessWarmupSeconds int      `envconfig:"READINESS_WARMUP_SECONDS" default:"1"`
	ShutdownTimeoutSeconds int      `envconfig:"SHUTDOWN_TIMEOUT_SECONDS" default:"10"`
	ConfigMapEnvVar        string   `envconfig:"CONFIG_MAP_ENV_VAR" default:""`
	SecretUsername         string   `envconfig:"SECRET_USERNAME" default:""`
	SecretPassword         string   `envconfig:"SECRET_PASSWORD" default:""`
	PodName                string   `envconfig:"POD_NAME" default:""`
	ReportRounds           int      `envconfig:"REPORT_ROUNDS" default:"200"`
	Postgres               Postgres `envconfig:"POSTGRES"`
}

type Postgres struct {
	Host     string `envconfig:"HOST" default:"localhost"`
	Port     int    `envconfig:"PORT" default:"5432"`
	User     string `envconfig:"USER" default:""`
	Pass     string `envconfig:"PASSWORD" default:""`
	DB       string `envconfig:"DB" default:""`
	MaxConns int    `envconfig:"MAX_CONNS" default:"10"`
}

// Load читает окружение с префиксом APP_.
func Load() (Config, error) {
	var c Config
	if err := envconfig.Process("APP", &c); err != nil {
		return Config{}, err
	}
	return c, nil
}

func (c Config) ReadinessWarmup() time.Duration {
	return time.Duration(c.ReadinessWarmupSeconds) * time.Second
}
func (c Config) ShutdownTimeout() time.Duration {
	return time.Duration(c.ShutdownTimeoutSeconds) * time.Second
}
