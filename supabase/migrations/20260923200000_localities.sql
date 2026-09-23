-- Localitățile din RO, AT, DE și HU: sate, comune, orașe (ADR-0011)
--
-- Tabelul places trece de la 38 de orașe de pe coridor la toate localitățile din cele patru țări
-- (peste 100.000, din GeoNames; licență CC BY 4.0, cu mențiunea sursei pe site):
--   * mai multe localități pot avea același nume în aceeași țară („Satu Nou”); se deosebesc prin
--     județ/land/megye (admin_name) și coordonate;
--   * căutare tolerantă: fără diacritice, ß → ss, ae/oe/ue → a/o/u, denumiri uzuale („Viena”),
--     începutul numelui și nume asemănătoare (trigrame);
--   * ordinea rezultatelor: nume exact, denumire uzuală, începutul numelui, asemănare; la egalitate,
--     orașele de pe coridor, apoi populația;
--   * importul (scripts/import-places.mjs) scrie doar prin import_places, cu cheia de sistem.
-- Cele 38 de orașe existente își păstrează identificatorii (rutele firmelor le folosesc).

create extension if not exists pg_trgm with schema extensions;

create or replace function public.place_norm(p text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select btrim(regexp_replace(
           replace(replace(replace(
             lower(translate(replace(replace(coalesce(p, ''), 'ß', 'ss'), 'ẞ', 'ss'),
                             'ăĂâÂîÎșȘşŞțȚţŢáÁàÀäÄãÃåÅāĀéÉèÈëËêÊěĚíÍìÌïÏóÓòÒöÖőŐôÔõÕøØúÚùÙüÜűŰûÛůŮçÇčČćĆñÑńŃňŇłŁźŹżŻžŽšŠśŚýÝÿŸđĐďĎřŘťŤľĽğĞıIİ',
                             'aaaaiissssttttaaaaaaaaaaaaeeeeeeeeeeiiiiiioooooooooooooouuuuuuuuuuuuccccccnnnnnnllzzzzzzssssyyyyddddrrttllggiii')),
             'ae', 'a'), 'oe', 'o'), 'ue', 'u'),
           '[^a-z0-9]+', ' ', 'g'));
$$;

alter table public.places drop constraint if exists places_name_country_key;
alter table public.places
  add column admin_name  text,
  add column kind        text not null default 'city' check (kind in ('city', 'town', 'village', 'locality')),
  add column population  int not null default 0 check (population >= 0),
  add column alt_names   text[] not null default '{}',
  add column source      text not null default 'core' check (source in ('core', 'geonames', 'manual')),
  add column source_id   text,
  add column name_norm   text not null default '',
  add column alt_norms   text[] not null default '{}';

create unique index places_source_uidx on public.places (source, source_id);
create index places_name_norm_trgm on public.places using gin (name_norm extensions.gin_trgm_ops);
create index places_name_norm_prefix on public.places (name_norm text_pattern_ops);
create index places_alt_norms on public.places using gin (alt_norms);
create index places_country_idx on public.places (country);

create or replace function public.places_norm_trigger()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.name_norm := public.place_norm(new.name);
  new.alt_norms := coalesce((select array_agg(distinct public.place_norm(a)) from unnest(new.alt_names) a
                             where public.place_norm(a) <> '' and public.place_norm(a) <> public.place_norm(new.name)), '{}');
  return new;
end;
$$;
create trigger places_norm before insert or update of name, alt_names on public.places
for each row execute function public.places_norm_trigger();

-- Cele 38 de orașe de pe coridor: județ/land și denumiri uzuale.
update public.places p set admin_name = v.admin_name, kind = 'city'
from (values
  ('Timișoara', 'Timiș'),
  ('Arad', 'Arad'),
  ('Lugoj', 'Timiș'),
  ('Caransebeș', 'Caraș-Severin'),
  ('Reșița', 'Caraș-Severin'),
  ('Deva', 'Hunedoara'),
  ('Hunedoara', 'Hunedoara'),
  ('Alba Iulia', 'Alba'),
  ('Sibiu', 'Sibiu'),
  ('Cluj-Napoca', 'Cluj'),
  ('Oradea', 'Bihor'),
  ('Brașov', 'Brașov'),
  ('Craiova', 'Dolj'),
  ('București', 'București'),
  ('Nădlac', 'Arad'),
  ('Szeged', 'Csongrád-Csanád'),
  ('Makó', 'Csongrád-Csanád'),
  ('Budapest', 'Budapest'),
  ('Győr', 'Győr-Moson-Sopron'),
  ('Wien', 'Wien'),
  ('St. Pölten', 'Niederösterreich'),
  ('Linz', 'Oberösterreich'),
  ('Wels', 'Oberösterreich'),
  ('Salzburg', 'Salzburg'),
  ('Graz', 'Steiermark'),
  ('Innsbruck', 'Tirol'),
  ('Passau', 'Bayern'),
  ('Regensburg', 'Bayern'),
  ('München', 'Bayern'),
  ('Augsburg', 'Bayern'),
  ('Ingolstadt', 'Bayern'),
  ('Ulm', 'Baden-Württemberg'),
  ('Stuttgart', 'Baden-Württemberg'),
  ('Nürnberg', 'Bayern'),
  ('Mannheim', 'Baden-Württemberg'),
  ('Frankfurt am Main', 'Hessen'),
  ('Köln', 'Nordrhein-Westfalen'),
  ('Berlin', 'Berlin')
) as v(name, admin_name)
where p.name = v.name and p.source = 'core';

update public.places p set alt_names = v.alt_names
from (values
  ('Wien', array['Viena', 'Vienna']),
  ('München', array['Munich', 'Monaco di Baviera']),
  ('Köln', array['Colonia', 'Cologne']),
  ('Nürnberg', array['Nuremberg']),
  ('București', array['Bucharest']),
  ('St. Pölten', array['Sankt Pölten']),
  ('Frankfurt am Main', array['Frankfurt']),
  ('Cluj-Napoca', array['Cluj'])
) as v(name, alt_names)
where p.name = v.name and p.source = 'core';

update public.places set name = name where name_norm = '';  -- normalizarea pentru rândurile existente

-- ---------- căutare ----------

create or replace function public.search_places(p_query text, p_country text default null, p_limit int default 8)
returns table (
  id uuid, name text, admin_name text, country char(2), kind text,
  lat double precision, lng double precision, population int, match text
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  with q as (select public.place_norm(left(p_query, 80)) as n)
  select p.id, p.name, p.admin_name, p.country, p.kind,
         st_y(p.location::geometry), st_x(p.location::geometry), p.population,
         case when p.name_norm = q.n then 'exact'
              when p.alt_norms @> array[q.n] then 'alias'
              when p.name_norm like q.n || '%' then 'prefix'
              when p.alt_norms <> '{}' and exists (select 1 from unnest(p.alt_norms) a where a like q.n || '%') then 'prefix'
              else 'similar' end
  from public.places p, q
  where length(q.n) >= 2
    and (p_country is null or p.country = upper(p_country))
    and (p.name_norm = q.n
         or p.alt_norms @> array[q.n]
         or p.name_norm like q.n || '%'
         -- începutul unei denumiri uzuale („Vien” → Viena → Wien); doar localitățile mari au astfel de denumiri
         or (p.alt_norms <> '{}' and exists (select 1 from unnest(p.alt_norms) a where a like q.n || '%'))
         or (length(q.n) >= 4 and p.name_norm % q.n))
  order by case when p.name_norm = q.n then 0
                when p.alt_norms @> array[q.n] then 1
                when p.name_norm like q.n || '%' then 2
                when p.alt_norms <> '{}' and exists (select 1 from unnest(p.alt_norms) a where a like q.n || '%') then 2
                else 3 end,
           (p.source = 'core') desc,
           p.population desc,
           similarity(p.name_norm, q.n) desc,
           p.name
  limit least(greatest(coalesce(p_limit, 8), 1), 20);
$$;

create or replace function public.get_places(p_ids uuid[])
returns table (id uuid, name text, admin_name text, country char(2), kind text,
               lat double precision, lng double precision)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select p.id, p.name, p.admin_name, p.country, p.kind, st_y(p.location::geometry), st_x(p.location::geometry)
  from public.places p
  where p.id = any(p_ids[1:20]);
$$;

-- public_places întoarce de acum doar orașele de pe coridor (restul se caută cu search_places).
create or replace function public.public_places()
returns table (id uuid, name text, country char(2), lat double precision, lng double precision)
language sql stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select p.id, p.name, p.country, st_y(p.location::geometry), st_x(p.location::geometry)
  from public.places p where p.source = 'core' order by p.country, p.name;
$$;

-- ---------- import (doar cheia de sistem) ----------

create or replace function public.import_places(p_rows jsonb)
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_count int;
begin
  with r as (
    select x.source_id, left(trim(x.name), 120) as name, left(nullif(trim(x.admin_name), ''), 120) as admin_name,
           upper(x.country) as country, coalesce(x.kind, 'locality') as kind, greatest(coalesce(x.population, 0), 0) as population,
           coalesce(x.alt_names, '{}') as alt_names,
           st_setsrid(st_makepoint(x.lng, x.lat), 4326)::geography as location
    from jsonb_to_recordset(p_rows) as x(source_id text, name text, admin_name text, country text, kind text,
                                          population int, lat double precision, lng double precision, alt_names text[])
    where x.source_id is not null and coalesce(trim(x.name), '') <> '' and upper(x.country) in ('RO', 'AT', 'DE', 'HU')
      and x.lat between -90 and 90 and x.lng between -180 and 180
      and coalesce(x.kind, 'locality') in ('city', 'town', 'village', 'locality')
  ), fresh as (
    -- orașele de pe coridor rămân cele existente (rutele firmelor le folosesc): nu le dublăm
    select r.* from r
    where not exists (select 1 from public.places c
                      where c.source = 'core' and c.country = r.country
                        and c.name_norm = public.place_norm(r.name)
                        and st_dwithin(c.location, r.location, 15000))
  ), up as (
    insert into public.places (name, country, location, admin_name, kind, population, alt_names, source, source_id)
    select name, country, location, admin_name, kind, population, alt_names, 'geonames', source_id from fresh
    on conflict (source, source_id) do update
      set name = excluded.name, country = excluded.country, location = excluded.location,
          admin_name = excluded.admin_name, kind = excluded.kind, population = excluded.population,
          alt_names = excluded.alt_names
    returning 1
  )
  select count(*)::int into v_count from up;
  return v_count;
end;
$$;

revoke execute on function public.places_norm_trigger() from public, anon, authenticated;
revoke execute on function public.search_places(text, text, int), public.get_places(uuid[]) from public;
grant execute on function public.search_places(text, text, int), public.get_places(uuid[]) to anon, authenticated;
revoke execute on function public.import_places(jsonb) from public, anon, authenticated;
grant execute on function public.import_places(jsonb) to service_role;
revoke execute on function public.place_norm(text) from public, anon;
grant execute on function public.place_norm(text) to authenticated, service_role;
