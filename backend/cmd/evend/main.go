package main

import (
	"context"
	"embed"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"syscall"
	"time"
	_ "time/tzdata" // distroless has no zoneinfo; Amsterdam week math needs it

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/api"
	"github.com/marcoBroccoli/thisiseven/backend/internal/auth"
	"github.com/marcoBroccoli/thisiseven/backend/internal/config"
	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
)

//go:embed migrations/*.sql
var migrations embed.FS

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	cfg, err := config.Load()
	if err != nil {
		slog.Error("config", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("db", "err", err)
		os.Exit(1)
	}
	defer db.Close()
	if err := waitForDB(ctx, db); err != nil {
		slog.Error("db unreachable", "err", err)
		os.Exit(1)
	}
	if err := migrate(ctx, db); err != nil {
		slog.Error("migrate", "err", err)
		os.Exit(1)
	}

	app := &api.API{
		DB: db,
		Google: google.New(cfg.GoogleClientID, cfg.GoogleClientSecret,
			cfg.GoogleOAuthBase, cfg.GoogleAPIBase),
	}
	if app.Google.Configured() {
		go app.RunGmailPoller(ctx, 30*time.Minute)
		slog.Info("gmail poller on", "every", "30m")
	}
	handler := api.Router(app, auth.NewVerifier(cfg.JWTSecret), cfg.GoTrueURL)

	server := &http.Server{
		Addr:              cfg.Addr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		WriteTimeout:      30 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	slog.Info("evend listening", "addr", cfg.Addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("serve", "err", err)
		os.Exit(1)
	}
}

func waitForDB(ctx context.Context, db *pgxpool.Pool) error {
	deadline := time.Now().Add(30 * time.Second)
	for {
		if err := db.Ping(ctx); err == nil {
			return nil
		} else if time.Now().After(deadline) {
			return err
		}
		time.Sleep(time.Second)
	}
}

// migrate runs embedded SQL files in name order, tracked in
// schema_migrations — tiny on purpose, no framework.
func migrate(ctx context.Context, db *pgxpool.Pool) error {
	if _, err := db.Exec(ctx, `create table if not exists schema_migrations (
		name text primary key, applied_at timestamptz not null default now())`); err != nil {
		return err
	}
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		return err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)
	for _, name := range names {
		var exists bool
		if err := db.QueryRow(ctx,
			`select exists(select 1 from schema_migrations where name = $1)`, name).Scan(&exists); err != nil {
			return err
		}
		if exists {
			continue
		}
		sql, err := migrations.ReadFile("migrations/" + name)
		if err != nil {
			return err
		}
		if _, err := db.Exec(ctx, string(sql)); err != nil {
			return err
		}
		if _, err := db.Exec(ctx,
			`insert into schema_migrations (name) values ($1)`, name); err != nil {
			return err
		}
		slog.Info("migrated", "file", name)
	}
	return nil
}
