-- 1000 — Company Admin: localități, rute-șablon, creare cursă din șablon
-- Rutele se construiesc din localități cu coordonate cunoscute, fără geocodare plătită.
-- Firma își salvează rutele obișnuite (ex. „Timișoara – München prin Wien”), apoi
-- creează curse din ele în câteva secunde.

create table public.places (
  id        uuid primary key default gen_random_uuid(),
  name      text not null,
  country   char(2) not null,
  location  extensions.geography(Point, 4326) not null,
  unique (name, country)
);

insert into public.places (name, country, location)
select name, country, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography
from (values
  ('Timișoara', 'RO', 45.7489, 21.2087), ('Arad', 'RO', 46.1866, 21.3123),
  ('Lugoj', 'RO', 45.6886, 21.9031),     ('Caransebeș', 'RO', 45.4214, 22.2219),
  ('Reșița', 'RO', 45.3008, 21.8892),    ('Deva', 'RO', 45.8833, 22.9000),
  ('Hunedoara', 'RO', 45.7697, 22.9203), ('Alba Iulia', 'RO', 46.0667, 23.5833),
  ('Sibiu', 'RO', 45.7983, 24.1256),     ('Cluj-Napoca', 'RO', 46.7712, 23.6236),
  ('Oradea', 'RO', 47.0465, 21.9189),    ('Brașov', 'RO', 45.6427, 25.5887),
  ('Craiova', 'RO', 44.3302, 23.7949),   ('București', 'RO', 44.4268, 26.1025),
  ('Nădlac', 'RO', 46.1667, 20.7500),
  ('Szeged', 'HU', 46.2530, 20.1414),    ('Makó', 'HU', 46.2167, 20.4833),
  ('Budapest', 'HU', 47.4979, 19.0402),  ('Győr', 'HU', 47.6875, 17.6504),
  ('Wien', 'AT', 48.2082, 16.3738),      ('St. Pölten', 'AT', 48.2047, 15.6256),
  ('Linz', 'AT', 48.3069, 14.2858),      ('Wels', 'AT', 48.1575, 14.0289),
  ('Salzburg', 'AT', 47.8095, 13.0550),  ('Graz', 'AT', 47.0707, 15.4395),
  ('Innsbruck', 'AT', 47.2692, 11.4041),
  ('Passau', 'DE', 48.5667, 13.4319),    ('Regensburg', 'DE', 49.0134, 12.1016),
  ('München', 'DE', 48.1351, 11.5820),   ('Augsburg', 'DE', 48.3705, 10.8978),
  ('Ingolstadt', 'DE', 48.7665, 11.4258), ('Ulm', 'DE', 48.4011, 9.9876),
  ('Stuttgart', 'DE', 48.7758, 9.1829),  ('Nürnberg', 'DE', 49.4521, 11.0767),
  ('Mannheim', 'DE', 49.4875, 8.4660),   ('Frankfurt am Main', 'DE', 50.1109, 8.6821),
  ('Köln', 'DE', 50.9375, 6.9603),       ('Berlin', 'DE', 52.5200, 13.4050)
) as p(name, country, lat, lng);

create table public.route_templates (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies (id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  created_at  timestamptz not null default now(),
  unique (company_id, name),
  unique (id, company_id)
);

create table public.route_template_points (
  template_id  uuid not null,
  company_id   uuid not null,
  seq          int  not null check (seq >= 0),
  place_id     uuid not null references public.places (id),
  primary key (template_id, seq),
  foreign key (template_id, company_id) references public.route_templates (id, company_id) on delete cascade
);

alter table public.places                enable row level security;
alter table public.route_templates       enable row level security;
alter table public.route_template_points enable row level security;

create policy places_read on public.places for select to authenticated using (true);
create policy places_write on public.places for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy route_templates_select on public.route_templates for select to authenticated
  using (public.is_company_staff(company_id));
create policy route_templates_write on public.route_templates for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_write(company_id));

create policy route_template_points_select on public.route_template_points for select to authenticated
  using (public.is_company_staff(company_id));
create policy route_template_points_write on public.route_template_points for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_write(company_id));

grant select, insert, update, delete on public.places, public.route_templates,
  public.route_template_points to authenticated;

-- Salvează un șablon cu punctele lui, într-o singură tranzacție.
-- security invoker: RLS se aplică normal utilizatorului.
create or replace function public.save_route_template(
  p_company_id  uuid,
  p_name        text,
  p_place_ids   uuid[]
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if coalesce(array_length(p_place_ids, 1), 0) < 2 then
    raise exception 'INVALID_ROUTE' using errcode = '22023';
  end if;

  insert into public.route_templates (company_id, name)
  values (p_company_id, trim(p_name))
  returning id into v_id;

  insert into public.route_template_points (template_id, company_id, seq, place_id)
  select v_id, p_company_id, ord - 1, place_id
  from unnest(p_place_ids) with ordinality as u(place_id, ord);

  return v_id;
end;
$$;

-- Creează o cursă dintr-un șablon: copiază punctele în trip_route_points.
create or replace function public.create_trip_from_template(
  p_template_id  uuid,
  p_vehicle_id   uuid,
  p_driver_id    uuid,
  p_departure_at timestamptz,
  p_title        text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public, extensions, pg_temp
as $$
declare
  v_company uuid;
  v_title   text;
  v_points  int;
  v_trip    uuid;
begin
  select company_id into v_company from public.route_templates where id = p_template_id;
  if v_company is null then
    raise exception 'TEMPLATE_NOT_FOUND' using errcode = 'P0002';
  end if;

  select count(*),
         string_agg(pl.name, ' – ' order by rtp.seq)
           filter (where rtp.seq = 0 or rtp.seq = (select max(seq) from public.route_template_points
                                                    where template_id = p_template_id))
    into v_points, v_title
  from public.route_template_points rtp
  join public.places pl on pl.id = rtp.place_id
  where rtp.template_id = p_template_id;

  if v_points < 2 then
    raise exception 'INVALID_ROUTE' using errcode = '22023';
  end if;

  insert into public.trips (company_id, vehicle_id, driver_id, title, departure_at)
  values (v_company, p_vehicle_id, p_driver_id, coalesce(nullif(trim(p_title), ''), v_title), p_departure_at)
  returning id into v_trip;

  insert into public.trip_route_points (trip_id, company_id, seq, name, location)
  select v_trip, v_company, rtp.seq, pl.name, pl.location
  from public.route_template_points rtp
  join public.places pl on pl.id = rtp.place_id
  where rtp.template_id = p_template_id;

  return v_trip;
end;
$$;

revoke execute on function public.save_route_template(uuid, text, uuid[]) from public, anon;
revoke execute on function public.create_trip_from_template(uuid, uuid, uuid, timestamptz, text) from public, anon;
grant execute on function public.save_route_template(uuid, text, uuid[]) to authenticated;
grant execute on function public.create_trip_from_template(uuid, uuid, uuid, timestamptz, text) to authenticated;
