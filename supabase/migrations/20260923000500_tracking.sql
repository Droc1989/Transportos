-- 0500 — Poziții GPS, evenimente de cursă, notificări trimise
-- Poziția curentă e separată de istoric (master plan §9).

create table public.vehicle_positions_current (
  vehicle_id   uuid primary key,
  company_id   uuid not null,
  trip_id      uuid,
  location     extensions.geography(Point, 4326) not null,
  speed_kmh    real,
  heading_deg  real check (heading_deg is null or (heading_deg >= 0 and heading_deg < 360)),
  recorded_at  timestamptz not null,
  foreign key (vehicle_id, company_id) references public.vehicles (id, company_id) on delete cascade
);

-- Istoric partiționat lunar. Retenție și rărire: vezi docs/adr/0003.
create table public.vehicle_positions (
  id           bigint generated always as identity,
  company_id   uuid not null,
  vehicle_id   uuid not null,
  trip_id      uuid,
  location     extensions.geography(Point, 4326) not null,
  speed_kmh    real,
  heading_deg  real,
  recorded_at  timestamptz not null,
  primary key (id, recorded_at),
  unique (vehicle_id, recorded_at)          -- aceeași poziție trimisă de două ori e ignorată
) partition by range (recorded_at);
create index vehicle_positions_trip_idx on public.vehicle_positions (trip_id, recorded_at);

create or replace function public.ensure_position_partitions(p_months_ahead int default 2)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_start date := date_trunc('month', now())::date;
  v_from  date;
  v_to    date;
  v_name  text;
begin
  for i in 0..p_months_ahead loop
    v_from := (v_start + make_interval(months => i))::date;
    v_to   := (v_from + interval '1 month')::date;
    v_name := format('vehicle_positions_%s', to_char(v_from, 'YYYY_MM'));
    execute format(
      'create table if not exists public.%I partition of public.vehicle_positions for values from (%L) to (%L)',
      v_name, v_from, v_to
    );
    execute format('alter table public.%I enable row level security', v_name);
  end loop;
end;
$$;

-- Partiție de rezervă pentru poziții cu ceas greșit, ca inserarea să nu eșueze.
create table public.vehicle_positions_default partition of public.vehicle_positions default;
alter table public.vehicle_positions_default enable row level security;

select public.ensure_position_partitions(2);

create table public.trip_events (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null,
  trip_id          uuid not null,
  booking_id       uuid,
  type             public.trip_event_type not null,
  payload          jsonb not null default '{}'::jsonb,
  idempotency_key  text not null,
  occurred_at      timestamptz not null default now(),
  created_by       uuid,
  unique (company_id, idempotency_key),
  foreign key (trip_id, company_id)    references public.trips (id, company_id) on delete cascade,
  foreign key (booking_id, company_id) references public.bookings (id, company_id) on delete cascade
);
create index trip_events_trip_idx on public.trip_events (trip_id, occurred_at);

-- Fiecare notificare (ex. ETA_30, ETA_10, ARRIVED) pleacă o singură dată pe rezervare.
create table public.notifications_sent (
  booking_id  uuid not null,
  company_id  uuid not null,
  kind        text not null check (kind ~ '^[A-Z0-9_]+$'),
  channel     text not null check (channel in ('PUSH', 'SMS', 'WHATSAPP', 'EMAIL')),
  sent_at     timestamptz not null default now(),
  primary key (booking_id, kind),
  foreign key (booking_id, company_id) references public.bookings (id, company_id) on delete cascade
);
