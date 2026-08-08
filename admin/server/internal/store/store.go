// Package store owns the database handle, the admin-schema migration runner
// and the first-admin bootstrap.
//
// The admin service shares evend's Postgres but not its migration chain: these
// files are tracked in admin.schema_migrations, so the two services can be
// deployed, rolled back and reasoned about independently.
package store

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"log/slog"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/admin/internal/adminauth"
)

type DB = *pgxpool.Pool

func Open(ctx context.Context, dsn string) (DB, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse dsn: %w", err)
	}
	// The console is read-mostly and low-traffic; a small pool keeps it from
	// ever being the reason evend cannot get a connection.
	cfg.MaxConns = 8
	cfg.MinConns = 1
	cfg.MaxConnIdleTime = 5 * time.Minute
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	return pool, nil
}

// WaitReady blocks until the database answers or the deadline passes — compose
// starts the admin container the moment Postgres accepts TCP, which is earlier
// than it accepts queries.
func WaitReady(ctx context.Context, db DB, within time.Duration) error {
	deadline := time.Now().Add(within)
	for {
		err := db.Ping(ctx)
		if err == nil {
			return nil
		}
		if time.Now().After(deadline) || ctx.Err() != nil {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
}

//go:embed migrations/*.sql
var migrations embed.FS

const migrationDir = "migrations"

// Migrate applies the admin-schema files in filename order, once each.
func Migrate(ctx context.Context, db DB) error {
	if _, err := db.Exec(ctx, `create schema if not exists admin`); err != nil {
		return fmt.Errorf("create schema: %w", err)
	}
	if _, err := db.Exec(ctx, `create table if not exists admin.schema_migrations (
		name text primary key, applied_at timestamptz not null default now())`); err != nil {
		return fmt.Errorf("migrations table: %w", err)
	}
	entries, err := migrations.ReadDir(migrationDir)
	if err != nil {
		return err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	for _, name := range names {
		var applied bool
		if err := db.QueryRow(ctx,
			`select exists(select 1 from admin.schema_migrations where name = $1)`,
			name).Scan(&applied); err != nil {
			return err
		}
		if applied {
			continue
		}
		body, err := migrations.ReadFile(migrationDir + "/" + name)
		if err != nil {
			return err
		}
		tx, err := db.Begin(ctx)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, string(body)); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("migration %s: %w", name, err)
		}
		if _, err := tx.Exec(ctx,
			`insert into admin.schema_migrations (name) values ($1)`, name); err != nil {
			_ = tx.Rollback(ctx)
			return err
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
		slog.Info("admin migration applied", "name", name)
	}
	return nil
}

// Bootstrap seeds the very first admin. It refuses to do anything once any
// admin row exists, so leaving the env vars in place cannot silently reset a
// password or resurrect a disabled account.
func Bootstrap(ctx context.Context, db DB, email, password string) error {
	if email == "" || password == "" {
		return nil
	}
	var count int
	if err := db.QueryRow(ctx, `select count(*) from admin.admin_users`).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		slog.Info("bootstrap skipped — admin users already exist", "count", count)
		return nil
	}
	hash, err := adminauth.HashPassword(password)
	if err != nil {
		return fmt.Errorf("bootstrap password: %w", err)
	}
	if _, err := db.Exec(ctx,
		`insert into admin.admin_users (email, password_hash, role) values ($1, $2, 'admin')`,
		email, hash); err != nil {
		return err
	}
	slog.Info("bootstrap admin created — TOTP enrolls on first login", "email", email)
	return nil
}

// ErrNotFound is returned by the query helpers so handlers can map a missing
// row to 404 without importing pgx.
var ErrNotFound = errors.New("not found")

func IsNoRows(err error) bool { return errors.Is(err, pgx.ErrNoRows) }
