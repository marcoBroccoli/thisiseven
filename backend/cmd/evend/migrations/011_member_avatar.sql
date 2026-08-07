-- Profile photos: path on the house-server volume + bump timestamp for ETag.
alter table members
  add column if not exists avatar_path text,
  add column if not exists avatar_updated_at timestamptz;
