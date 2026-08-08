// Package config reads the admin service's environment. Nothing here has a
// secret default: a missing DSN or bootstrap password is a startup error, not
// a silently insecure fallback.
package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	// Addr is the listen address, e.g. ":3025".
	Addr string
	// DatabaseURL points at the SAME Postgres evend uses. The admin service
	// owns only the `admin` schema; everything else it reads.
	DatabaseURL string
	// EvendBaseURL is probed by the health page (GET {base}/healthz).
	EvendBaseURL string
	// SessionTTL is how long a signed-in admin stays signed in.
	SessionTTL time.Duration
	// CookieSecure drops the Secure flag when explicitly disabled, so a plain
	// http://even-admin.home dev run can still hold a session.
	CookieSecure bool
	// BootstrapEmail/Password seed the first admin — only when the table is
	// empty. Set them once, then remove them from the environment.
	BootstrapEmail    string
	BootstrapPassword string
	// TOTPIssuer labels the entry in the authenticator app.
	TOTPIssuer string
}

func Load() (Config, error) {
	c := Config{
		Addr:              env("ADMIN_ADDR", ":3025"),
		DatabaseURL:       os.Getenv("ADMIN_DATABASE_URL"),
		EvendBaseURL:      env("ADMIN_EVEND_BASE_URL", "http://evend:8080"),
		CookieSecure:      env("ADMIN_COOKIE_SECURE", "true") != "false",
		BootstrapEmail:    strings.ToLower(strings.TrimSpace(os.Getenv("ADMIN_BOOTSTRAP_EMAIL"))),
		BootstrapPassword: os.Getenv("ADMIN_BOOTSTRAP_PASSWORD"),
		TOTPIssuer:        env("ADMIN_TOTP_ISSUER", "Even Admin"),
	}
	if c.DatabaseURL == "" {
		return c, errors.New("ADMIN_DATABASE_URL is required")
	}
	if _, err := url.Parse(c.DatabaseURL); err != nil {
		return c, fmt.Errorf("ADMIN_DATABASE_URL is not a URL: %w", err)
	}
	hours, err := strconv.Atoi(env("ADMIN_SESSION_HOURS", "12"))
	if err != nil || hours < 1 || hours > 24*30 {
		return c, errors.New("ADMIN_SESSION_HOURS must be an integer between 1 and 720")
	}
	c.SessionTTL = time.Duration(hours) * time.Hour
	if (c.BootstrapEmail == "") != (c.BootstrapPassword == "") {
		return c, errors.New("ADMIN_BOOTSTRAP_EMAIL and ADMIN_BOOTSTRAP_PASSWORD must be set together")
	}
	if c.BootstrapPassword != "" && len(c.BootstrapPassword) < 12 {
		return c, errors.New("ADMIN_BOOTSTRAP_PASSWORD must be at least 12 characters")
	}
	return c, nil
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
