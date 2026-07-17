package config

import (
	"fmt"
	"os"
)

// Config is 12-factor: everything from the environment, nothing on disk.
type Config struct {
	Addr         string // listen address, default :8080
	DatabaseURL  string
	JWTSecret    []byte // GoTrue's HS256 secret — evend only verifies
	GoTrueURL    string // internal URL the /auth/* proxy forwards to
}

func Load() (*Config, error) {
	c := &Config{
		Addr:        getenv("EVEN_ADDR", ":8080"),
		DatabaseURL: os.Getenv("EVEN_DATABASE_URL"),
		GoTrueURL:   getenv("EVEN_GOTRUE_URL", "http://gotrue:9999"),
	}
	if c.DatabaseURL == "" {
		return nil, fmt.Errorf("EVEN_DATABASE_URL is required")
	}
	secret := os.Getenv("EVEN_GOTRUE_JWT_SECRET")
	if secret == "" {
		return nil, fmt.Errorf("EVEN_GOTRUE_JWT_SECRET is required")
	}
	c.JWTSecret = []byte(secret)
	return c, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
