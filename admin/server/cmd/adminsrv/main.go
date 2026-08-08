// Command adminsrv is Even's operations console: a standalone Go service that
// reads evend's Postgres directly and owns nothing in it but the `admin`
// schema.
//
// It is deliberately a separate binary from evend. The console must be
// deployable, restartable and (if it ever misbehaves) killable without
// touching the API two people's household actually depends on.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // distroless carries no zoneinfo

	"github.com/marcoBroccoli/thisiseven/admin/internal/api"
	"github.com/marcoBroccoli/thisiseven/admin/internal/config"
	"github.com/marcoBroccoli/thisiseven/admin/internal/store"
	"github.com/marcoBroccoli/thisiseven/admin/internal/web"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	cfg, err := config.Load()
	if err != nil {
		slog.Error("config", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := store.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("open database", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	if err := store.WaitReady(ctx, db, 30*time.Second); err != nil {
		slog.Error("database unreachable", "err", err)
		os.Exit(1)
	}
	if err := store.Migrate(ctx, db); err != nil {
		slog.Error("admin migrations", "err", err)
		os.Exit(1)
	}
	if err := store.Bootstrap(ctx, db, cfg.BootstrapEmail, cfg.BootstrapPassword); err != nil {
		slog.Error("bootstrap admin", "err", err)
		os.Exit(1)
	}

	app := &api.API{
		DB:           db,
		SessionTTL:   cfg.SessionTTL,
		CookieSecure: cfg.CookieSecure,
		TOTPIssuer:   cfg.TOTPIssuer,
		EvendBaseURL: cfg.EvendBaseURL,
		HTTP:         &http.Client{Timeout: 3 * time.Second},
	}
	if !cfg.CookieSecure {
		slog.Warn("session cookie is not Secure — plain-HTTP mode, do not use on the public domain")
	}

	server := &http.Server{
		Addr:              cfg.Addr,
		Handler:           api.Router(app, web.Handler()),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       2 * time.Minute,
	}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	slog.Info("even admin listening", "addr", cfg.Addr, "evend", cfg.EvendBaseURL)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("serve", "err", err)
		os.Exit(1)
	}
}
