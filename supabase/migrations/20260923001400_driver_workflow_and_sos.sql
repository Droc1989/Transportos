-- 1400 — Fluxul șoferului pe cursă și SOS
--
-- Funcțiile pot fi apelate de șoferul cursei sau de personalul firmei. Nu depind de
-- abonament: o cursă începută se termină normal și la restanță (ADR-0001).
-- Fiecare acțiune e idempotentă: a doua apăsare pe același buton nu schimbă nimic.
--
-- Coduri de eroare noi: STOP_STATE_INVALID (acțiune nepotrivită pentru oprire/cursă).

create or replace function public._require_trip_actor(p_trip_id uuid)
returns uuid
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.trips where id = p_trip_id;
  if v_company is null then
    raise exception 'TRIP_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not (public.is_company_staff(v_company) or public.is_trip_driver(p_trip_id)) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  return v_company;
end;
$$;

create or replace function public._trip_event(
  p_company uuid, p_trip uuid, p_booking uuid, p_type public.trip_event_type,
  p_key text, p_payload jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.trip_events (company_id, trip_id, booking_id, type, payload, idempotency_key, created_by)
  values (p_company, p_trip, p_booking, p_type, coalesce(p_payload, '{}'::jsonb), p_key, auth.uid())
  on conflict (company_id, idempotency_key) do nothing;
$$;

-- ---------- cursa ----------

create or replace function public.start_trip(p_trip_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := public._require_trip_actor(p_trip_id);
  v_trip    public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if v_trip.status = 'IN_PROGRESS' then
    return;
  end if;
  if v_trip.status <> 'PLANNED' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;

  update public.trips set status = 'IN_PROGRESS' where id = p_trip_id;
  update public.vehicles set status = 'EN_ROUTE' where id = v_trip.vehicle_id;
  update public.bookings set status = 'DRIVER_ASSIGNED'
  where trip_id = p_trip_id and status = 'CONFIRMED' and v_trip.driver_id is not null;
  perform public._trip_event(v_company, p_trip_id, null, 'TRIP_STARTED', 'start:' || p_trip_id);
end;
$$;

create or replace function public.complete_trip(p_trip_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := public._require_trip_actor(p_trip_id);
  v_trip    public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if v_trip.status = 'COMPLETED' then
    return;
  end if;
  if v_trip.status <> 'IN_PROGRESS' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;

  -- Cine era încă la bord a ajuns la destinație.
  update public.bookings set status = 'COMPLETED'
  where trip_id = p_trip_id and status = 'ON_BOARD';
  update public.trip_stops set status = 'DONE', arrived_at = coalesce(arrived_at, now())
  where trip_id = p_trip_id and kind = 'DROPOFF' and status in ('PLANNED', 'APPROACHING', 'ARRIVED')
    and booking_id in (select id from public.bookings where trip_id = p_trip_id and status = 'COMPLETED');

  update public.trips set status = 'COMPLETED' where id = p_trip_id;
  update public.vehicles set status = 'AVAILABLE'
  where id = v_trip.vehicle_id and status in ('EN_ROUTE', 'PICKUP', 'IN_SERVICE', 'BREAK', 'ASSIGNED');
  perform public._trip_event(v_company, p_trip_id, null, 'TRIP_COMPLETED', 'complete:' || p_trip_id);
end;
$$;

-- ---------- opriri ----------

create or replace function public._lock_stop(p_stop_id uuid)
returns public.trip_stops
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_stop public.trip_stops%rowtype;
begin
  select * into v_stop from public.trip_stops where id = p_stop_id;
  if v_stop.id is null then
    raise exception 'BOOKING_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform public._require_trip_actor(v_stop.trip_id);
  perform 1 from public.trips where id = v_stop.trip_id and status = 'IN_PROGRESS' for update;
  if not found then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;
  select * into v_stop from public.trip_stops where id = p_stop_id for update;
  return v_stop;
end;
$$;

-- Clientul a urcat.
create or replace function public.board_passenger(p_stop_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_stop public.trip_stops := public._lock_stop(p_stop_id);
begin
  if v_stop.kind <> 'PICKUP' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;
  if v_stop.status = 'DONE' then
    return;
  end if;
  if v_stop.status = 'SKIPPED' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;

  update public.trip_stops set status = 'DONE', arrived_at = coalesce(arrived_at, now()) where id = p_stop_id;
  update public.bookings set status = 'ON_BOARD' where id = v_stop.booking_id;
  perform public._trip_event(v_stop.company_id, v_stop.trip_id, v_stop.booking_id,
                             'PASSENGER_ON_BOARD', 'board:' || p_stop_id);
end;
$$;

-- Clientul a coborât la destinație.
create or replace function public.complete_dropoff(p_stop_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_stop public.trip_stops := public._lock_stop(p_stop_id);
  v_booking_status public.booking_status;
begin
  if v_stop.kind <> 'DROPOFF' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;
  if v_stop.status = 'DONE' then
    return;
  end if;
  select status into v_booking_status from public.bookings where id = v_stop.booking_id;
  if v_booking_status <> 'ON_BOARD' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;

  update public.trip_stops set status = 'DONE', arrived_at = coalesce(arrived_at, now()) where id = p_stop_id;
  update public.bookings set status = 'COMPLETED' where id = v_stop.booking_id;
  -- Locul devine liber pentru restul traseului (segmentele de după coborâre).
  update public.booking_seats set released_at = now()
  where booking_id = v_stop.booking_id and released_at is null;
end;
$$;

-- Clientul nu s-a prezentat. Locul se eliberează pentru restul cursei.
create or replace function public.mark_no_show(p_stop_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_stop public.trip_stops := public._lock_stop(p_stop_id);
begin
  if v_stop.kind <> 'PICKUP' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;
  if (select status from public.bookings where id = v_stop.booking_id) = 'NO_SHOW' then
    return;
  end if;
  if v_stop.status = 'DONE' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;

  update public.bookings set status = 'NO_SHOW' where id = v_stop.booking_id;
  update public.trip_stops set status = 'SKIPPED'
  where booking_id = v_stop.booking_id and status <> 'DONE';
  update public.booking_seats set released_at = now()
  where booking_id = v_stop.booking_id and released_at is null;
end;
$$;

-- ---------- evenimente pe drum: pauză, alimentare, incident ----------

create or replace function public.record_trip_event(
  p_trip_id          uuid,
  p_type             public.trip_event_type,
  p_idempotency_key  text,
  p_payload          jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := public._require_trip_actor(p_trip_id);
  v_vehicle uuid;
begin
  if p_type not in ('BREAK_STARTED', 'BREAK_ENDED', 'FUEL_ADDED', 'INCIDENT', 'ROUTE_DEVIATION') then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;
  if coalesce(length(p_idempotency_key), 0) < 8 then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023', detail = 'idempotency_key';
  end if;

  perform public._trip_event(v_company, p_trip_id, null, p_type, p_idempotency_key, p_payload);

  select vehicle_id into v_vehicle from public.trips where id = p_trip_id and status = 'IN_PROGRESS';
  if v_vehicle is not null then
    if p_type = 'BREAK_STARTED' then
      update public.vehicles set status = 'BREAK' where id = v_vehicle and status <> 'EMERGENCY';
    elsif p_type = 'BREAK_ENDED' then
      update public.vehicles set status = 'EN_ROUTE' where id = v_vehicle and status = 'BREAK';
    end if;
  end if;
end;
$$;

-- ---------- cursele șoferului ----------

create or replace function public.get_driver_trips(p_from timestamptz, p_to timestamptz)
returns table (
  trip_id        uuid,
  title          text,
  status         public.trip_status,
  departure_at   timestamptz,
  vehicle_id     uuid,
  vehicle_label  text,
  vehicle_plate  text,
  active_stops   int
)
language sql stable
security invoker
set search_path = public, pg_temp
as $$
  select t.id, t.title, t.status, t.departure_at, v.id, v.label, v.plate,
         (select count(*)::int from public.trip_stops s
          where s.trip_id = t.id and s.status in ('PLANNED', 'APPROACHING', 'ARRIVED'))
  from public.trips t
  join public.vehicles v on v.id = t.vehicle_id
  join public.drivers d on d.id = t.driver_id
  where d.user_id = auth.uid()
    and t.status in ('PLANNED', 'IN_PROGRESS')
    and t.departure_at between p_from and p_to
  order by t.departure_at;
$$;

-- ---------- SOS (master plan §17) ----------

create table public.emergency_events (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  vehicle_id        uuid not null,
  trip_id           uuid,
  driver_user_id    uuid,
  severity          text not null check (severity in ('POSSIBLE', 'CONFIRMED')),
  source            text not null check (source in ('MANUAL', 'AUTO')),
  status            text not null default 'OPEN'
                    check (status in ('OPEN', 'ACKNOWLEDGED', 'RESOLVED', 'CANCELLED')),
  location          extensions.geography(Point, 4326),
  last_speed_kmh    real,
  idempotency_key   text not null,
  created_at        timestamptz not null default now(),
  confirmed_at      timestamptz,
  acknowledged_by   uuid,
  acknowledged_at   timestamptz,
  resolved_at       timestamptz,
  unique (company_id, idempotency_key),
  unique (id, company_id),
  foreign key (vehicle_id, company_id) references public.vehicles (id, company_id)
);
create index emergency_events_open_idx on public.emergency_events (company_id, status, created_at desc);

-- Pasagerii de la bord în momentul confirmării. Acces strict: doar personalul firmei.
create table public.emergency_event_passengers (
  event_id     uuid not null,
  company_id   uuid not null,
  booking_id   uuid not null,
  full_name    text not null,
  phone        text not null,
  passengers   int not null,
  primary key (event_id, booking_id),
  foreign key (event_id, company_id) references public.emergency_events (id, company_id) on delete cascade
);

alter table public.emergency_events enable row level security;
alter table public.emergency_event_passengers enable row level security;
create policy emergency_select on public.emergency_events for select to authenticated
  using (public.is_company_staff(company_id) or driver_user_id = auth.uid());
create policy emergency_passengers_select on public.emergency_event_passengers for select to authenticated
  using (public.is_company_staff(company_id));
grant select on public.emergency_events, public.emergency_event_passengers to authenticated;
revoke insert, update, delete on public.emergency_events, public.emergency_event_passengers from authenticated;

create or replace function public._confirm_emergency(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.emergency_events%rowtype;
begin
  update public.emergency_events
  set severity = 'CONFIRMED', confirmed_at = coalesce(confirmed_at, now())
  where id = p_event_id and status = 'OPEN'
  returning * into v_event;
  if v_event.id is null then
    return;
  end if;

  update public.vehicles set status = 'EMERGENCY' where id = v_event.vehicle_id;

  if v_event.trip_id is not null then
    insert into public.emergency_event_passengers (event_id, company_id, booking_id, full_name, phone, passengers)
    select v_event.id, v_event.company_id, b.id, c.full_name, c.phone, b.passengers
    from public.bookings b join public.customers c on c.id = b.customer_id
    where b.trip_id = v_event.trip_id and b.status = 'ON_BOARD'
    on conflict do nothing;

    perform public._trip_event(v_event.company_id, v_event.trip_id, null, 'INCIDENT',
                               'sos:' || v_event.id,
                               jsonb_build_object('emergency_event_id', v_event.id, 'source', v_event.source));
  end if;
end;
$$;

-- SOS manual (CONFIRMED imediat) sau detecție automată (POSSIBLE, cu numărătoare pe telefon).
-- În fereastra de 5 minute, un nou semnal pentru același vehicul întoarce evenimentul deschis.
create or replace function public.raise_emergency(
  p_vehicle_id       uuid,
  p_trip_id          uuid,
  p_lat              double precision,
  p_lng              double precision,
  p_source           text,
  p_idempotency_key  text,
  p_speed_kmh        real default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_company uuid;
  v_id      uuid;
begin
  select company_id into v_company from public.vehicles where id = p_vehicle_id;
  if v_company is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not (public.is_company_staff(v_company)
          or (p_trip_id is not null and public.is_trip_driver(p_trip_id)
              and exists (select 1 from public.trips where id = p_trip_id and vehicle_id = p_vehicle_id))) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_source not in ('MANUAL', 'AUTO') then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;

  select id into v_id from public.emergency_events
  where company_id = v_company and idempotency_key = p_idempotency_key;
  if v_id is null then
    select id into v_id from public.emergency_events
    where vehicle_id = p_vehicle_id and status = 'OPEN' and created_at > now() - interval '5 minutes'
    order by created_at desc limit 1;
  end if;

  if v_id is null then
    insert into public.emergency_events
      (company_id, vehicle_id, trip_id, driver_user_id, severity, source, location, last_speed_kmh, idempotency_key)
    values (v_company, p_vehicle_id, p_trip_id, auth.uid(),
            case when p_source = 'MANUAL' then 'CONFIRMED' else 'POSSIBLE' end, p_source,
            case when p_lat is not null and p_lng is not null
                 then st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography end,
            p_speed_kmh, p_idempotency_key)
    returning id into v_id;
  end if;

  -- Manualul confirmă întotdeauna, chiar dacă exista deja un eveniment automat deschis.
  if p_source = 'MANUAL' then
    perform public._confirm_emergency(v_id);
  end if;
  return v_id;
end;
$$;

-- Șoferul apasă „SUNT BINE” în timpul numărătorii: evenimentul automat se anulează.
create or replace function public.dismiss_emergency(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.emergency_events%rowtype;
begin
  select * into v_event from public.emergency_events where id = p_event_id for update;
  if v_event.id is null
     or not (public.is_company_staff(v_event.company_id) or v_event.driver_user_id = auth.uid()) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_event.severity <> 'POSSIBLE' or v_event.status <> 'OPEN' then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;
  update public.emergency_events set status = 'CANCELLED', resolved_at = now() where id = p_event_id;
end;
$$;

-- Numărătoarea a expirat fără răspuns: aplicația șoferului sau un job confirmă alerta.
create or replace function public.confirm_emergency(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.emergency_events%rowtype;
begin
  select * into v_event from public.emergency_events where id = p_event_id;
  if v_event.id is null
     or not (public.is_company_staff(v_event.company_id) or v_event.driver_user_id = auth.uid()) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  perform public._confirm_emergency(p_event_id);
end;
$$;

-- Dispecerul confirmă că a văzut alerta, apoi o închide.
create or replace function public.acknowledge_emergency(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.emergency_events where id = p_event_id;
  if v_company is null or not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.emergency_events
  set status = 'ACKNOWLEDGED', acknowledged_by = auth.uid(), acknowledged_at = now()
  where id = p_event_id and status = 'OPEN';
end;
$$;

create or replace function public.resolve_emergency(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.emergency_events%rowtype;
begin
  select * into v_event from public.emergency_events where id = p_event_id for update;
  if v_event.id is null or not public.is_company_staff(v_event.company_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_event.status in ('RESOLVED', 'CANCELLED') then
    return;
  end if;
  update public.emergency_events
  set status = 'RESOLVED', resolved_at = now(),
      acknowledged_by = coalesce(acknowledged_by, auth.uid()),
      acknowledged_at = coalesce(acknowledged_at, now())
  where id = p_event_id;
  update public.vehicles
  set status = case when exists (select 1 from public.trips
                                 where vehicle_id = v_event.vehicle_id and status = 'IN_PROGRESS')
                    then 'EN_ROUTE' else 'AVAILABLE' end::public.vehicle_status
  where id = v_event.vehicle_id and status = 'EMERGENCY';
end;
$$;

revoke execute on function public._require_trip_actor(uuid),
  public._trip_event(uuid, uuid, uuid, public.trip_event_type, text, jsonb),
  public._lock_stop(uuid), public._confirm_emergency(uuid)
  from public, anon, authenticated;
revoke execute on function public.start_trip(uuid), public.complete_trip(uuid), public.board_passenger(uuid),
  public.complete_dropoff(uuid), public.mark_no_show(uuid),
  public.record_trip_event(uuid, public.trip_event_type, text, jsonb),
  public.get_driver_trips(timestamptz, timestamptz),
  public.raise_emergency(uuid, uuid, double precision, double precision, text, text, real),
  public.dismiss_emergency(uuid), public.confirm_emergency(uuid),
  public.acknowledge_emergency(uuid), public.resolve_emergency(uuid)
  from public, anon;
grant execute on function public.start_trip(uuid), public.complete_trip(uuid), public.board_passenger(uuid),
  public.complete_dropoff(uuid), public.mark_no_show(uuid),
  public.record_trip_event(uuid, public.trip_event_type, text, jsonb),
  public.get_driver_trips(timestamptz, timestamptz),
  public.raise_emergency(uuid, uuid, double precision, double precision, text, text, real),
  public.dismiss_emergency(uuid), public.confirm_emergency(uuid),
  public.acknowledge_emergency(uuid), public.resolve_emergency(uuid)
  to authenticated;
