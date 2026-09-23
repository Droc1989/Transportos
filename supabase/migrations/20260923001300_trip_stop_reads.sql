-- 1300 — Citirea opririlor și a punctelor de traseu cu coordonate (lat/lng)
-- PostgREST întoarce coloanele geography ca WKB; aplicația are nevoie de numere simple.
-- Funcțiile sunt security invoker: RLS decide ce vede utilizatorul.

create or replace function public.get_trip_stops(p_trip_id uuid)
returns table (
  id             uuid,
  seq            int,
  kind           public.stop_kind,
  status         public.stop_status,
  booking_id     uuid,
  address        text,
  lat            double precision,
  lng            double precision,
  planned_at     timestamptz,
  customer_name  text,
  customer_phone text,
  passengers     int,
  pickup_notes   text
)
language sql stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select s.id, s.seq, s.kind, s.status, s.booking_id, s.address,
         st_y(s.location::geometry), st_x(s.location::geometry),
         s.planned_at, c.full_name, c.phone, b.passengers, b.pickup_notes
  from public.trip_stops s
  join public.bookings b  on b.id = s.booking_id
  join public.customers c on c.id = b.customer_id
  where s.trip_id = p_trip_id and s.status <> 'SKIPPED'
  order by s.seq;
$$;

create or replace function public.get_trip_route_points(p_trip_id uuid)
returns table (seq int, name text, lat double precision, lng double precision)
language sql stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select rp.seq, rp.name, st_y(rp.location::geometry), st_x(rp.location::geometry)
  from public.trip_route_points rp
  where rp.trip_id = p_trip_id
  order by rp.seq;
$$;

revoke execute on function public.get_trip_stops(uuid), public.get_trip_route_points(uuid) from public, anon;
grant execute on function public.get_trip_stops(uuid), public.get_trip_route_points(uuid) to authenticated;
