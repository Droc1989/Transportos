-- DOAR PENTRU TESTE pe un Postgres simplu (CI). În Supabase acestea există deja.
-- Nu rula acest fișier pe un proiect Supabase.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

create table if not exists auth.users (
  id                  uuid primary key,
  email               text,
  phone               text,          -- ca în Supabase (autentificare cu telefon)
  phone_confirmed_at  timestamptz
);

-- Ca în Supabase: utilizatorul curent vine din claim-ul JWT „sub”, fie din setarea veche
-- (request.jwt.claim.sub, folosită de testele SQL), fie din JSON-ul pus de PostgREST.
create or replace function auth.uid()
returns uuid
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Ca în Supabase: service_role are acces complet la obiectele create de migrații.
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
