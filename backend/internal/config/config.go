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

	// Google integration (Gmail discovery + Calendar writes). Empty client
	// id/secret disables the feature (its endpoints answer 409).
	GoogleClientID     string
	GoogleIOSClientID  string
	GoogleClientSecret string
	GoogleOAuthBase    string // test override; default https://oauth2.googleapis.com
	GoogleAPIBase      string // test override; default https://www.googleapis.com
}

func Load() (*Config, error) {
	c := &Config{
		Addr:               getenv("EVEN_ADDR", ":8080"),
		DatabaseURL:        os.Getenv("EVEN_DATABASE_URL"),
		GoTrueURL:          getenv("EVEN_GOTRUE_URL", "http://gotrue:9999"),
		GoogleClientID:     os.Getenv("GOOGLE_OAUTH_CLIENT_ID"),
		GoogleIOSClientID:  os.Getenv("GOOGLE_IOS_CLIENT_ID"),
		GoogleClientSecret: os.Getenv("GOOGLE_OAUTH_CLIENT_SECRET"),
		GoogleOAuthBase:    os.Getenv("GOOGLE_OAUTH_BASE"),
		GoogleAPIBase:      os.Getenv("GOOGLE_API_BASE"),
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
