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
//
// Legacy CONFIG_MAP_ENV_VAR удалён.

type Config struct {
	Port                   string `envconfig:"PORT" default:"8080"`
	ReadinessWarmupSeconds int    `envconfig:"READINESS_WARMUP_SECONDS" default:"1"`
	ShutdownTimeoutSeconds int    `envconfig:"SHUTDOWN_TIMEOUT_SECONDS" default:"10"`
	ConfigMapEnvVar        string `envconfig:"CONFIG_MAP_ENV_VAR" default:""`
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
