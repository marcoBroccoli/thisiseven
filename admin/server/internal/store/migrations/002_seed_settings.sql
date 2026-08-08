-- A few keys so the settings editor is never an empty box on a fresh install.
-- These describe intent, not behaviour: evend does not read admin.settings.
insert into admin.settings (key, value, description, updated_by) values
    ('gmail_poll_minutes', '30'::jsonb,
     'Minutes between Gmail poller passes. evend currently hard-codes 30m; changing this does nothing until the poller reads it.',
     'system'),
    ('signups_open', 'true'::jsonb,
     'Whether new GoTrue signups are accepted. Mirrors GOTRUE_DISABLE_SIGNUP; informational only.',
     'system'),
    ('maintenance_banner', '""'::jsonb,
     'Text to show in-app during maintenance. Empty string means no banner.',
     'system')
on conflict (key) do nothing;
