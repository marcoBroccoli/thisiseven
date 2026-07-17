-- GoTrue keeps its tables in the auth schema; the app owns public.
-- GoTrue connects as the db superuser (single-tenant box), but its bundled
-- migrations grant to Supabase's standard roles — they must exist.
create schema if not exists auth;
do $$ begin
  if not exists (select from pg_roles where rolname = 'postgres') then
    create role postgres nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end $$;
