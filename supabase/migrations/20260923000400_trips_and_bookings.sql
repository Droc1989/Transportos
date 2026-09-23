-- 0400 — Curse, puncte de traseu, rezervări, locuri pe segmente, opriri
-- Modelul de locuri e descris în docs/adr/0002-locuri-pe-segmente.md.

create table public.trips (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies (id) on delete cascade,
  vehicle_id    uuid not null,
  driver_id     uuid,
  service_type  public.service_type not null default 'PASSENGER',
  status        public.trip_status not null default 'PLANNED',
  title         text not null,               -- ex. Timișoara – München
  departure_at  timestamptz not null,
  route_line    extensions.geography(LineString, 4326), -- reconstruit automat din punctele de traseu
  created_at    timestamptz not null default now(),
  unique (id, company_id),
  foreign key (vehicle_id, company_id) references public.vehicles (id, company_id),
  foreign key (driver_id, company_id)  references public.drivers (id, company_id)
);
create index trips_company_departure_idx on public.trips (company_id, departure_at);
create index trips_route_line_gix on public.trips using gist (route_line);

-- Puncte fixe ale traseului (orașe/zone), ordonate. Capacitatea se calculează pe
-- segmentele dintre ele: segmentul k = porțiunea dintre punctul k și k+1.
create table public.trip_route_points (
  trip_id     uuid not null,
  company_id  uuid not null,
  seq         int  not null check (seq >= 0),
  name        text not null,
  location    extensions.geography(Point, 4326) not null,
  planned_at  timestamptz,
  primary key (trip_id, seq),
  foreign key (trip_id, company_id) references public.trips (id, company_id) on delete cascade
);

create or replace function public.rebuild_trip_route_line()
returns trigger
language plpgsql
set search_path = public, extensions, pg_temp
as $$
declare
  v_trip uuid := coalesce(new.trip_id, old.trip_id);
begin
  update public.trips t
  set route_line = (
    select case when count(*) >= 2
                then st_makeline(p.location::geometry order by p.seq)::geography
           end
    from public.trip_route_points p
    where p.trip_id = v_trip
  )
  where t.id = v_trip;
  return null;
end;
$$;

create trigger trip_route_points_rebuild
after insert or update or delete on public.trip_route_points
for each row execute function public.rebuild_trip_route_line();

create table public.bookings (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  trip_id           uuid not null,
  customer_id       uuid not null,
  status            public.booking_status not null default 'HELD',
  passengers        int  not null check (passengers between 1 and 60),
  from_seq          int  not null,
  to_seq            int  not null,
  pickup_address    text,
  pickup_location   extensions.geography(Point, 4326),
  pickup_notes      text,
  dropoff_address   text,
  dropoff_location  extensions.geography(Point, 4326),
  luggage_notes     text,
  price_cents       int check (price_cents is null or price_cents >= 0),
  currency          text not null default 'EUR' check (currency in ('EUR', 'RON')),
  payment_method    public.payment_method not null default 'CASH_TO_DRIVER',
  hold_expires_at   timestamptz,
  cancel_reason     text,
  idempotency_key   text,
  created_by        uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (from_seq >= 0 and to_seq > from_seq),
  check (status <> 'HELD' or hold_expires_at is not null),
  unique (id, company_id),
  unique (company_id, idempotency_key),
  foreign key (trip_id, company_id)     references public.trips (id, company_id) on delete cascade,
  foreign key (customer_id, company_id) references public.customers (id, company_id)
);
create index bookings_trip_idx on public.bookings (trip_id);
create index bookings_customer_idx on public.bookings (customer_id);

-- Un rând per loc ocupat. segment = [from_seq, to_seq) în punctele de traseu.
-- Constrângerea de excludere garantează la nivel de bază de date că același loc
-- nu poate fi ocupat de două rezervări active pe segmente care se suprapun.
create table public.booking_seats (
  booking_id   uuid not null,
  company_id   uuid not null,
  trip_id      uuid not null,
  seat_no      int  not null check (seat_no >= 1),
  segment      int4range not null check (not isempty(segment)),
  released_at  timestamptz,
  primary key (booking_id, seat_no),
  foreign key (booking_id, company_id) references public.bookings (id, company_id) on delete cascade,
  foreign key (trip_id, company_id)    references public.trips (id, company_id) on delete cascade,
  constraint booking_seats_no_overlap exclude using gist (
    trip_id with =,
    seat_no with =,
    segment with &&
  ) where (released_at is null)
);

-- Opririle reale (door-to-door), în ordinea în care le face șoferul.
create table public.trip_stops (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null,
  trip_id     uuid not null,
  booking_id  uuid not null,
  kind        public.stop_kind not null,
  seq         int  not null,
  address     text,
  location    extensions.geography(Point, 4326),
  planned_at  timestamptz,
  eta_at      timestamptz,
  status      public.stop_status not null default 'PLANNED',
  arrived_at  timestamptz,
  constraint trip_stops_order unique (trip_id, seq) deferrable initially deferred,
  unique (booking_id, kind),
  foreign key (trip_id, company_id)    references public.trips (id, company_id) on delete cascade,
  foreign key (booking_id, company_id) references public.bookings (id, company_id) on delete cascade
);
create index trip_stops_location_gix on public.trip_stops using gist (location);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger bookings_touch before update on public.bookings
for each row execute function public.touch_updated_at();
