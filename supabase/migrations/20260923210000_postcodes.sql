-- Codurile poștale din RO, AT, DE, HU, legate de localități (ADR-0011, completare)
--
-- Sursa: GeoNames, baza separată de coduri poștale (CC BY 4.0), importată cu
-- `npm run import:postcodes` (după localități). Fiecare cod se leagă de localitatea cu același nume
-- cea mai apropiată (sub 20 km); dacă nu există, de cea mai apropiată localitate sub 3 km; altfel
-- codul e sărit (numărat în rezultatul importului).
--
-- search_places înțelege și codurile: „80331”, „8033” (început), „D-80331”, „80331 München”.
-- Rezultatele au coloana nouă postcode (codul potrivit, sau null la căutarea după nume).

create index if not exists places_location_gist on public.places using gist (location);

create table public.place_postcodes (
  country   char(2) not null check (country in ('RO', 'AT', 'DE', 'HU')),
  postcode  text not null check (postcode ~ '^[0-9]{3,6}$'),
  place_id  uuid not null references public.places (id) on delete cascade,
  primary key (country, postcode, place_id)
);
create index place_postcodes_prefix on public.place_postcodes (postcode text_pattern_ops);
create index place_postcodes_place on public.place_postcodes (place_id);

alter table public.place_postcodes enable row level security;
create policy place_postcodes_read on public.place_postcodes for select to anon, authenticated using (true);
grant select on public.place_postcodes to anon, authenticated;

-- ---------- căutarea: după nume sau după codul poștal ----------

drop function public.search_places(text, text, int);
create function public.search_places(p_query text, p_country text default null, p_limit int default 8)
returns table (
  id uuid, name text, admin_name text, country char(2), kind text,
  lat double precision, lng double precision, population int, match text, postcode text
)
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_text  text := left(coalesce(p_query, ''), 80);
  v_limit int := least(greatest(coalesce(p_limit, 8), 1), 20);
  v_m     text[];
  v_code  text;
  v_rest  text;
  v_n     text := public.place_norm(v_text);
begin
  -- Cod poștal la început, cu prefix de țară opțional („D-80331”, „RO 307241”), apoi eventual numele.
  v_m := regexp_match(v_text, '^\s*(?:[A-Za-z]{1,2}\s*-\s*|[A-Za-z]{1,2}\s+)?([0-9]{3,6})(?:\s+(.*))?\s*$');
  if v_m is not null then
    v_code := v_m[1];
    v_rest := public.place_norm(coalesce(v_m[2], ''));
    return query
      select x.id, x.name, x.admin_name, x.country, x.kind, x.lat, x.lng, x.population, x.match, x.postcode
      from (
        select distinct on (p.id)
               p.id, p.name, p.admin_name, p.country, p.kind,
               st_y(p.location::geometry) as lat, st_x(p.location::geometry) as lng, p.population,
               case when pc.postcode = v_code then 'postcode' else 'postcode_prefix' end as match,
               pc.postcode, (pc.postcode = v_code) as exact_code
        from public.place_postcodes pc
        join public.places p on p.id = pc.place_id
        where pc.postcode like v_code || '%'
          and (p_country is null or pc.country = upper(p_country))
          and (v_rest = '' or p.name_norm like v_rest || '%' or p.alt_norms @> array[v_rest])
        order by p.id, (pc.postcode = v_code) desc, pc.postcode
      ) x
      order by x.exact_code desc, x.population desc, x.postcode, x.name
      limit v_limit;
    return;
  end if;

  return query
    select p.id, p.name, p.admin_name, p.country, p.kind,
           st_y(p.location::geometry), st_x(p.location::geometry), p.population,
           case when p.name_norm = v_n then 'exact'
                when p.alt_norms @> array[v_n] then 'alias'
                when p.name_norm like v_n || '%' then 'prefix'
                when p.alt_norms <> '{}' and exists (select 1 from unnest(p.alt_norms) a where a like v_n || '%') then 'prefix'
                else 'similar' end,
           null::text
    from public.places p
    where length(v_n) >= 2
      and (p_country is null or p.country = upper(p_country))
      and (p.name_norm = v_n
           or p.alt_norms @> array[v_n]
           or p.name_norm like v_n || '%'
           or (p.alt_norms <> '{}' and exists (select 1 from unnest(p.alt_norms) a where a like v_n || '%'))
           or (length(v_n) >= 4 and p.name_norm % v_n))
    order by case when p.name_norm = v_n then 0
                  when p.alt_norms @> array[v_n] then 1
                  when p.name_norm like v_n || '%' then 2
                  when p.alt_norms <> '{}' and exists (select 1 from unnest(p.alt_norms) a where a like v_n || '%') then 2
                  else 3 end,
             (p.source = 'core') desc,
             p.population desc,
             similarity(p.name_norm, v_n) desc,
             p.name
    limit v_limit;
end;
$$;

-- ---------- import (doar cheia de sistem) ----------

create or replace function public.import_postcodes(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_linked  int;
  v_total   int;
begin
  with r as (
    select upper(x.country) as country, regexp_replace(coalesce(x.postcode, ''), '\s', '', 'g') as postcode,
           public.place_norm(x.name) as name_norm,
           st_setsrid(st_makepoint(x.lng, x.lat), 4326)::geography as loc
    from jsonb_to_recordset(p_rows) as x(country text, postcode text, name text, lat double precision, lng double precision)
    where upper(x.country) in ('RO', 'AT', 'DE', 'HU')
      and regexp_replace(coalesce(x.postcode, ''), '\s', '', 'g') ~ '^[0-9]{3,6}$'
      and x.lat between -90 and 90 and x.lng between -180 and 180
  ), matched as (
    select r.country, r.postcode,
           coalesce(
             -- aceeași denumire, cea mai apropiată, sub 20 km
             (select p.id from public.places p
              where p.country = r.country and p.name_norm = r.name_norm and st_dwithin(p.location, r.loc, 20000)
              order by p.location <-> r.loc limit 1),
             -- altfel, cea mai apropiată localitate, sub 3 km
             (select p.id from public.places p
              where p.country = r.country and st_dwithin(p.location, r.loc, 3000)
              order by p.location <-> r.loc limit 1)
           ) as place_id
    from r
  ), ins as (
    insert into public.place_postcodes (country, postcode, place_id)
    select country, postcode, place_id from matched where place_id is not null
    on conflict do nothing
    returning 1
  )
  select (select count(*) from ins), (select count(*) from matched where place_id is not null)
    into v_linked, v_total;
  return jsonb_build_object('linked', v_total, 'new', v_linked,
                            'skipped', jsonb_array_length(p_rows) - v_total);
end;
$$;

revoke execute on function public.search_places(text, text, int) from public;
grant execute on function public.search_places(text, text, int) to anon, authenticated;
revoke execute on function public.import_postcodes(jsonb) from public, anon, authenticated;
grant execute on function public.import_postcodes(jsonb) to service_role;
