-- The admin console's own tables. They live in a dedicated `admin` schema so
-- evend's migration chain never sees them and `\dt` in the app schema stays
-- the product's story. Nothing here has a foreign key into the product tables:
-- an audit row or a queued notification must outlive the household it names,
-- and evend must stay free to drop and re-create anything it owns.

create schema if not exists admin;

create table if not exists admin.admin_users (
    id               uuid primary key default gen_random_uuid(),
    email            text not null unique,             -- stored lowercased
    password_hash    text not null,                    -- bcrypt
    totp_secret      text,                             -- base32, null until enrolled
    totp_enrolled_at timestamptz,
    role             text not null default 'admin'
        check (role in ('admin', 'viewer')),
    disabled_at      timestamptz,
    last_login_at    timestamptz,
    created_at       timestamptz not null default now()
);

-- Sessions are server-side: the cookie carries a random token, the row carries
-- its sha256. A stolen database dump cannot be replayed as a cookie, and
-- revocation is a single UPDATE.
create table if not exists admin.sessions (
    id            uuid primary key default gen_random_uuid(),
    token_hash    text not null unique,
    admin_user_id uuid not null references admin.admin_users(id) on delete cascade,
    ip            text,
    user_agent    text,
    created_at    timestamptz not null default now(),
    expires_at    timestamptz not null,
    revoked_at    timestamptz
);
create index if not exists admin_sessions_user_idx on admin.sessions(admin_user_id);
create index if not exists admin_sessions_expiry_idx on admin.sessions(expires_at);

-- The gap between "password accepted" and "TOTP accepted". Short-lived, single
-- use, and the only place a not-yet-confirmed TOTP secret is allowed to sit.
create table if not exists admin.login_challenges (
    id               uuid primary key default gen_random_uuid(),
    token_hash       text not null unique,
    admin_user_id    uuid not null references admin.admin_users(id) on delete cascade,
    secret_candidate text,           -- set only during first-login enrollment
    attempts         int not null default 0,
    created_at       timestamptz not null default now(),
    expires_at       timestamptz not null
);

-- Every login decision, successful or not. Feeds the rate limiter (which reads
-- the last 15 minutes) and the health page's "recent failures" number.
create table if not exists admin.login_attempts (
    id         bigserial primary key,
    email      text not null,
    ip         text,
    ok         boolean not null,
    reason     text,
    created_at timestamptz not null default now()
);
create index if not exists admin_login_attempts_recent_idx
    on admin.login_attempts(created_at desc);
create index if not exists admin_login_attempts_email_idx
    on admin.login_attempts(email, created_at desc);

-- Every write the console performs. before/after are whole-row JSON so a
-- mistake can be read back and reversed by hand.
create table if not exists admin.audit_log (
    id            bigserial primary key,
    admin_user_id uuid references admin.admin_users(id) on delete set null,
    actor_email   text not null,
    action        text not null,          -- e.g. 'household.invite.revoke'
    target_type   text,                   -- 'household' | 'user' | 'setting' | ...
    target_id     text,
    summary       text,
    before_json   jsonb,
    after_json    jsonb,
    ip            text,
    created_at    timestamptz not null default now()
);
create index if not exists admin_audit_recent_idx on admin.audit_log(created_at desc);
create index if not exists admin_audit_target_idx on admin.audit_log(target_type, target_id);

-- Operational key/value the console owns. evend does NOT read this table yet —
-- it is a staging area for flags that will be wired in deliberately, one at a
-- time, rather than a live remote-config channel.
create table if not exists admin.settings (
    key         text primary key,
    value       jsonb not null,
    description text,
    updated_at  timestamptz not null default now(),
    updated_by  text
);

-- Composed pushes wait here. The console fills the row; the APNs sender is a
-- later server-side job that will claim 'queued' rows, move them to 'sending'
-- and finish them. Nothing delivers today, and the UI says so.
create table if not exists admin.notification_outbox (
    id              uuid primary key default gen_random_uuid(),
    audience        text not null check (audience in ('all', 'household', 'user')),
    household_id    uuid,                 -- set when audience = 'household'
    user_id         uuid,                 -- set when audience = 'user'
    title           text not null,
    body            text not null,
    scheduled_at    timestamptz not null default now(),
    status          text not null default 'queued'
        check (status in ('queued', 'sending', 'sent', 'failed', 'cancelled')),
    recipient_count int not null default 0,   -- estimated at compose time
    delivered_count int not null default 0,
    error           text,
    created_by      text not null,
    created_at      timestamptz not null default now(),
    sent_at         timestamptz,
    constraint notification_target_matches_audience check (
        (audience = 'all'       and household_id is null and user_id is null) or
        (audience = 'household' and household_id is not null and user_id is null) or
        (audience = 'user'      and user_id is not null and household_id is null)
    )
);
create index if not exists admin_outbox_status_idx
    on admin.notification_outbox(status, scheduled_at);
create index if not exists admin_outbox_recent_idx
    on admin.notification_outbox(created_at desc);
