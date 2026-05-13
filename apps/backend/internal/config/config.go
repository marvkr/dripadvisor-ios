package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Env                string
	HTTPAddr           string
	DatabaseURL        string
	RedisAddr          string
	S3Endpoint         string
	S3AccessKey        string
	S3SecretKey        string
	S3Bucket           string
	S3Region           string
	S3UsePathStyle     bool
	JWTSigningSecret   string
	AppleBundleID      string
	AppleTeamID        string
	SessionTTLHours    int
	GeminiAPIKey       string
	FreeTryOnsPerWeek  int
	FreeStylistPerWeek int
}

func Load() (*Config, error) {
	c := &Config{
		Env:                env("ENV", "dev"),
		HTTPAddr:           env("HTTP_ADDR", ":8080"),
		DatabaseURL:        env("DATABASE_URL", "postgres://dripadvisor:dev@localhost:5432/dripadvisor?sslmode=disable"),
		RedisAddr:          env("REDIS_ADDR", "localhost:6379"),
		S3Endpoint:         env("S3_ENDPOINT", "http://localhost:9000"),
		S3AccessKey:        env("S3_ACCESS_KEY", "minioadmin"),
		S3SecretKey:        env("S3_SECRET_KEY", "minioadmin"),
		S3Bucket:           env("S3_BUCKET", "dripadvisor-dev"),
		S3Region:           env("S3_REGION", "us-east-1"),
		S3UsePathStyle:     envBool("S3_USE_PATH_STYLE", true),
		JWTSigningSecret:   env("JWT_SIGNING_SECRET", ""),
		AppleBundleID:      env("APPLE_BUNDLE_ID", "com.dripadvisor.DripAdvisor"),
		AppleTeamID:        env("APPLE_TEAM_ID", ""),
		SessionTTLHours:    envInt("SESSION_TTL_HOURS", 720),
		GeminiAPIKey:       env("GEMINI_API_KEY", ""),
		FreeTryOnsPerWeek:  envInt("FREE_TRYONS_PER_WEEK", 3),
		FreeStylistPerWeek: envInt("FREE_STYLIST_REPLIES_PER_WEEK", 2),
	}
	if len(c.JWTSigningSecret) < 32 {
		return nil, fmt.Errorf("JWT_SIGNING_SECRET must be >= 32 bytes")
	}
	return c, nil
}

func env(k, def string) string {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		return v
	}
	return def
}

func envInt(k string, def int) int {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func envBool(k string, def bool) bool {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		switch strings.ToLower(v) {
		case "1", "true", "yes", "y", "on":
			return true
		case "0", "false", "no", "n", "off":
			return false
		}
	}
	return def
}
