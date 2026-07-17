-- Which OAuth client minted the stored refresh token: token refresh must use
-- the same client. 'desktop' = loopback script flow, 'ios' = in-app PKCE flow.
alter table google_accounts
    add column if not exists client_kind text not null default 'desktop';
