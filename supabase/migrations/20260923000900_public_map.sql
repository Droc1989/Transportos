-- 0900 — Harta live publică de pe prima pagină
-- Regulile sunt în docs/adr/0004-harta-publica.md. Pe scurt: doar curse în mers,
-- cu locuri libere, de la firme care au ales asta; poziție rotunjită (~5 km)
-- și întârziată ~7 minute; fără șofer, număr auto sau pasageri.
-- Vizitatorii citesc doar acest tabel, niciodată pozițiile reale.

create table public.public_live_trips (
  trip_id         uuid primary key,
  company_name    text not null,
  heading_to      text not null,
  next_points     text[] not null,
  approx_lat      double precision not null,
  approx_lng      double precision not null,
  free_seats      int not null check (free_seats > 0),
  refreshed_at    timestamptz not null default now()
);

alter table public.public_live_trips enable row level security;
create policy public_live_trips_read on public.public_live_trips
  for select to anon, authenticated using (true);
grant select on public.public_live_trips to anon, authenticated;
revoke insert, update, delete on public.public_live_trips from authenticated;

-- Rulează o dată pe minut (pg_cron sau un job extern cu service_role).
create or replace function public.refresh_public_live_trips(
  p_delay     interval default interval '7 minutes',
  p_grid_deg  double precision default 0.05
)
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_count int;
begin
  delete from public.public_live_trips;

  insert into public.public_live_trips
    (trip_id, company_name, heading_to, next_points, approx_lat, approx_lng, free_seats)
  select
    t.id,
    c.name,
    last_pt.name,
    next_pts.names,
    st_y(st_snaptogrid(pos.location::geometry, p_grid_deg)),
    st_x(st_snaptogrid(pos.location::geometry, p_grid_deg)),
    seats.free
  from public.trips t
  join public.companies c        on c.id = t.company_id and c.status = 'ACTIVE'
  join public.company_settings s on s.company_id = t.company_id and s.show_on_public_map
  join public.vehicles v         on v.id = t.vehicle_id
  -- poziția de acum ~7 minute, nu mai veche de 30 de minute
  join lateral (
    select p.location, p.speed_kmh, p.recorded_at
    from public.vehicle_positions p
    where p.vehicle_id = t.vehicle_id
      and p.recorded_at <= now() - p_delay
      and p.recorded_at >  now() - p_delay - interval '30 minutes'
    order by p.recorded_at desc
    limit 1
  ) pos on true
  -- următorul punct de traseu = cel mai apropiat punct aflat după poziție
  join lateral (
    select rp.seq
    from public.trip_route_points rp
    where rp.trip_id = t.id
    order by rp.location <-> pos.location
    limit 1
  ) near on true
  join lateral (
    select array_agg(rp.name order by rp.seq) as names
    from public.trip_route_points rp
    where rp.trip_id = t.id and rp.seq > near.seq
  ) next_pts on true
  join lateral (
    select rp.name, rp.seq
    from public.trip_route_points rp
    where rp.trip_id = t.id
    order by rp.seq desc
    limit 1
  ) last_pt on true
  join lateral (
    select v.seats - count(distinct bs.seat_no) as free
    from public.booking_seats bs
    join public.bookings b on b.id = bs.booking_id
    where bs.trip_id = t.id
      and bs.released_at is null
      and bs.segment && int4range(near.seq, last_pt.seq)
      and not (b.status = 'HELD' and b.hold_expires_at < now())
  ) seats on true
  where t.status = 'IN_PROGRESS'
    and public.has_feature(t.company_id, 'public_map')
    and coalesce(pos.speed_kmh, 0) >= 5          -- vehiculele oprite nu apar
    and near.seq < last_pt.seq
    and next_pts.names is not null
    and seats.free > 0;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.refresh_public_live_trips(interval, double precision) from public, anon, authenticated;

-- În Supabase, cu extensia pg_cron activă:
-- select cron.schedule('refresh-public-map', '* * * * *',
--   $$select public.refresh_public_live_trips()$$);
