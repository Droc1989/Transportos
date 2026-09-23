-- 0700 — Funcții de domeniu: rezervări, potrivire curse, poziții GPS
-- Toate scrierile sensibile la concurență trec pe aici. Ordinea de blocare e
-- mereu: rândul cursei (FOR UPDATE), apoi rezervările ei. Constrângerea
-- booking_seats_no_overlap rămâne plasa de siguranță la nivel de bază de date.
--
-- Coduri de eroare (în MESSAGE), folosite de aplicație pentru mesaje traduse:
--   TRIP_NOT_FOUND, BOOKING_NOT_FOUND, FORBIDDEN, COMPANY_READ_ONLY, TRIP_CLOSED,
--   INVALID_SEGMENT, NOT_ENOUGH_SEATS, HOLD_EXPIRED, INVALID_POSITION

-- ---------- intern: eliberează rezervările HELD expirate ale unei curse ----------
create or replace function public._release_expired_holds(p_trip_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
begin
  with expired as (
    update public.bookings
    set status = 'CANCELLED', cancel_reason = 'HOLD_EXPIRED', hold_expires_at = null
    where trip_id = p_trip_id and status = 'HELD' and hold_expires_at < now()
    returning id
  )
  update public.booking_seats bs
  set released_at = now()
  from expired e
  where bs.booking_id = e.id and bs.released_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------- locuri libere pe o porțiune ----------
create or replace function public.free_seats(p_trip_id uuid, p_from_seq int, p_to_seq int)
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
  v_seats   int;
  v_taken   int;
begin
  select t.company_id, v.seats into v_company, v_seats
  from public.trips t
  join public.vehicles v on v.id = t.vehicle_id and v.company_id = t.company_id
  where t.id = p_trip_id;

  if v_company is null then
    raise exception 'TRIP_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not (public.is_company_staff(v_company) or public.is_trip_driver(p_trip_id)) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_to_seq <= p_from_seq then
    raise exception 'INVALID_SEGMENT' using errcode = '22023';
  end if;

  select count(distinct bs.seat_no) into v_taken
  from public.booking_seats bs
  join public.bookings b on b.id = bs.booking_id
  where bs.trip_id = p_trip_id
    and bs.released_at is null
    and bs.segment && int4range(p_from_seq, p_to_seq)
    and not (b.status = 'HELD' and b.hold_expires_at < now());

  return greatest(v_seats - v_taken, 0);
end;
$$;

-- ---------- rezervare ----------
create or replace function public.book_seats(
  p_trip_id          uuid,
  p_customer_id      uuid,
  p_passengers       int,
  p_from_seq         int,
  p_to_seq           int,
  p_pickup_address   text default null,
  p_pickup_lat       double precision default null,
  p_pickup_lng       double precision default null,
  p_pickup_notes     text default null,
  p_dropoff_address  text default null,
  p_dropoff_lat      double precision default null,
  p_dropoff_lng      double precision default null,
  p_price_cents      int default null,
  p_currency         text default 'EUR',
  p_payment_method   public.payment_method default 'CASH_TO_DRIVER',
  p_confirm          boolean default false,
  p_hold_minutes     int default 10,
  p_idempotency_key  text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_company   uuid;
  v_status    public.trip_status;
  v_seats     int;
  v_max_seq   int;
  v_existing  uuid;
  v_free      int[];
  v_booking   uuid;
  v_range     int4range;
begin
  -- 1. Blochează cursa: rezervările pe aceeași cursă se execută pe rând.
  select t.company_id, t.status, v.seats
    into v_company, v_status, v_seats
  from public.trips t
  join public.vehicles v on v.id = t.vehicle_id and v.company_id = t.company_id
  where t.id = p_trip_id
  for update of t;

  if v_company is null then
    raise exception 'TRIP_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not public.company_can_write(v_company) then
    raise exception 'COMPANY_READ_ONLY' using errcode = '42501';
  end if;
  if v_status in ('COMPLETED', 'CANCELLED') then
    raise exception 'TRIP_CLOSED' using errcode = '22023';
  end if;

  -- 2. Idempotență: aceeași cheie întoarce aceeași rezervare.
  if p_idempotency_key is not null then
    select id into v_existing from public.bookings
    where company_id = v_company and idempotency_key = p_idempotency_key;
    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  -- 3. Validări.
  select max(seq) into v_max_seq from public.trip_route_points where trip_id = p_trip_id;
  if v_max_seq is null or p_from_seq < 0 or p_to_seq > v_max_seq or p_to_seq <= p_from_seq then
    raise exception 'INVALID_SEGMENT' using errcode = '22023';
  end if;
  if p_passengers is null or p_passengers < 1 then
    raise exception 'INVALID_SEGMENT' using errcode = '22023', detail = 'passengers';
  end if;

  -- 4. Eliberează rezervările expirate, apoi caută locuri libere pe porțiune.
  perform public._release_expired_holds(p_trip_id);
  v_range := int4range(p_from_seq, p_to_seq);

  select array_agg(s order by s) into v_free
  from (
    select s
    from generate_series(1, v_seats) as s
    where not exists (
      select 1 from public.booking_seats bs
      where bs.trip_id = p_trip_id
        and bs.seat_no = s
        and bs.released_at is null
        and bs.segment && v_range
    )
    order by s
    limit p_passengers
  ) free;

  if coalesce(array_length(v_free, 1), 0) < p_passengers then
    raise exception 'NOT_ENOUGH_SEATS' using errcode = 'P0001',
      detail = format('available=%s', coalesce(array_length(v_free, 1), 0));
  end if;

  -- 5. Creează rezervarea și ocupă locurile.
  insert into public.bookings (
    company_id, trip_id, customer_id, status, passengers, from_seq, to_seq,
    pickup_address, pickup_location, pickup_notes,
    dropoff_address, dropoff_location,
    price_cents, currency, payment_method, hold_expires_at, idempotency_key, created_by
  ) values (
    v_company, p_trip_id, p_customer_id,
    case when p_confirm then 'CONFIRMED' else 'HELD' end::public.booking_status,
    p_passengers, p_from_seq, p_to_seq,
    p_pickup_address,
    case when p_pickup_lat is not null and p_pickup_lng is not null
         then st_setsrid(st_makepoint(p_pickup_lng, p_pickup_lat), 4326)::geography end,
    p_pickup_notes,
    p_dropoff_address,
    case when p_dropoff_lat is not null and p_dropoff_lng is not null
         then st_setsrid(st_makepoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography end,
    p_price_cents, p_currency, p_payment_method,
    case when p_confirm then null else now() + make_interval(mins => greatest(p_hold_minutes, 1)) end,
    p_idempotency_key, auth.uid()
  )
  returning id into v_booking;

  insert into public.booking_seats (booking_id, company_id, trip_id, seat_no, segment)
  select v_booking, v_company, p_trip_id, s, v_range
  from unnest(v_free) as s;

  return v_booking;
end;
$$;

-- ---------- confirmare ----------
create or replace function public.confirm_booking(p_booking_id uuid)
returns public.booking_status
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_trip     uuid;
  v_company  uuid;
  v_status   public.booking_status;
begin
  select trip_id, company_id into v_trip, v_company
  from public.bookings where id = p_booking_id;
  if v_trip is null then
    raise exception 'BOOKING_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  perform 1 from public.trips where id = v_trip for update;
  perform public._release_expired_holds(v_trip);

  select status into v_status from public.bookings where id = p_booking_id;
  if v_status = 'HELD' then
    update public.bookings
    set status = 'CONFIRMED', hold_expires_at = null
    where id = p_booking_id;
    return 'CONFIRMED';
  elsif v_status = 'CANCELLED' then
    raise exception 'HOLD_EXPIRED' using errcode = '22023';
  end if;
  return v_status; -- deja confirmată sau mai departe: operația e idempotentă
end;
$$;

-- ---------- anulare ----------
create or replace function public.cancel_booking(p_booking_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_trip     uuid;
  v_company  uuid;
begin
  select trip_id, company_id into v_trip, v_company
  from public.bookings where id = p_booking_id;
  if v_trip is null then
    raise exception 'BOOKING_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  perform 1 from public.trips where id = v_trip for update;

  update public.bookings
  set status = 'CANCELLED', cancel_reason = coalesce(p_reason, cancel_reason), hold_expires_at = null
  where id = p_booking_id and status not in ('CANCELLED', 'COMPLETED');

  update public.booking_seats
  set released_at = now()
  where booking_id = p_booking_id and released_at is null;
end;
$$;

-- ---------- potrivire curse pentru o adresă (dispecer) ----------
-- Întoarce cursele care trec aproape de preluare și de destinație, în direcția
-- bună (from_seq < to_seq) și cu locuri suficiente. Ocolul exact în minute se
-- calculează în aplicație, prin RoutingProvider (OSRM), doar pentru aceste curse.
create or replace function public.find_matching_trips(
  p_pickup_lat      double precision,
  p_pickup_lng      double precision,
  p_dropoff_lat     double precision,
  p_dropoff_lng     double precision,
  p_passengers      int,
  p_window_start    timestamptz,
  p_window_end      timestamptz,
  p_max_distance_m  double precision default 25000
)
returns table (
  trip_id             uuid,
  title               text,
  departure_at        timestamptz,
  vehicle_label       text,
  from_seq            int,
  from_name           text,
  to_seq              int,
  to_name             text,
  pickup_distance_m   double precision,
  dropoff_distance_m  double precision,
  free_seats          int
)
language sql
stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  with pts as (
    select st_setsrid(st_makepoint(p_pickup_lng, p_pickup_lat), 4326)::geography   as pickup,
           st_setsrid(st_makepoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography as dropoff
  ),
  candidates as (
    select t.id, t.title, t.departure_at, v.label,
           st_distance(t.route_line, pts.pickup)  as pickup_d,
           st_distance(t.route_line, pts.dropoff) as dropoff_d
    from public.trips t
    join public.vehicles v on v.id = t.vehicle_id and v.company_id = t.company_id
    cross join pts
    where t.status in ('PLANNED', 'IN_PROGRESS')
      and t.departure_at between p_window_start and p_window_end
      and t.route_line is not null
      and st_dwithin(t.route_line, pts.pickup,  p_max_distance_m)
      and st_dwithin(t.route_line, pts.dropoff, p_max_distance_m)
  ),
  with_seq as (
    select c.*,
      (select rp.seq from public.trip_route_points rp, pts
        where rp.trip_id = c.id order by rp.location <-> pts.pickup, rp.seq limit 1)  as f_seq,
      (select rp.seq from public.trip_route_points rp, pts
        where rp.trip_id = c.id order by rp.location <-> pts.dropoff, rp.seq desc limit 1) as t_seq
    from candidates c
  )
  select w.id, w.title, w.departure_at, w.label,
         w.f_seq, fp.name, w.t_seq, tp.name,
         w.pickup_d, w.dropoff_d,
         public.free_seats(w.id, w.f_seq, w.t_seq)
  from with_seq w
  join public.trip_route_points fp on fp.trip_id = w.id and fp.seq = w.f_seq
  join public.trip_route_points tp on tp.trip_id = w.id and tp.seq = w.t_seq
  where w.f_seq < w.t_seq
    and public.free_seats(w.id, w.f_seq, w.t_seq) >= p_passengers
  order by w.pickup_d, w.departure_at;
$$;

-- ---------- poziție GPS de la aplicația șoferului sau tracker ----------
-- Nu depinde de abonament: o cursă începută continuă și la restanță.
create or replace function public.ingest_position(
  p_vehicle_id   uuid,
  p_lat          double precision,
  p_lng          double precision,
  p_recorded_at  timestamptz,
  p_speed_kmh    real default null,
  p_heading_deg  real default null,
  p_trip_id      uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_company   uuid;
  v_location  geography;
  v_inserted  int;
begin
  select company_id into v_company from public.vehicles where id = p_vehicle_id;
  if v_company is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not (
    public.is_company_staff(v_company)
    or (p_trip_id is not null
        and public.is_trip_driver(p_trip_id)
        and exists (select 1 from public.trips
                    where id = p_trip_id and vehicle_id = p_vehicle_id))
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_lat not between -90 and 90 or p_lng not between -180 and 180
     or p_recorded_at > now() + interval '5 minutes' then
    raise exception 'INVALID_POSITION' using errcode = '22023';
  end if;

  v_location := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;

  insert into public.vehicle_positions
    (company_id, vehicle_id, trip_id, location, speed_kmh, heading_deg, recorded_at)
  values (v_company, p_vehicle_id, p_trip_id, v_location, p_speed_kmh, p_heading_deg, p_recorded_at)
  on conflict (vehicle_id, recorded_at) do nothing;
  get diagnostics v_inserted = row_count;

  insert into public.vehicle_positions_current as cur
    (vehicle_id, company_id, trip_id, location, speed_kmh, heading_deg, recorded_at)
  values (p_vehicle_id, v_company, p_trip_id, v_location, p_speed_kmh, p_heading_deg, p_recorded_at)
  on conflict (vehicle_id) do update
    set trip_id = excluded.trip_id,
        location = excluded.location,
        speed_kmh = excluded.speed_kmh,
        heading_deg = excluded.heading_deg,
        recorded_at = excluded.recorded_at
    where excluded.recorded_at > cur.recorded_at;

  return v_inserted > 0;
end;
$$;

-- ---------- șoferul a ajuns la o oprire ----------
create or replace function public.mark_stop_arrived(p_stop_id uuid)
returns void
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
  if not (public.is_company_staff(v_stop.company_id) or public.is_trip_driver(v_stop.trip_id)) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  update public.trip_stops
  set status = 'ARRIVED', arrived_at = coalesce(arrived_at, now())
  where id = p_stop_id and status in ('PLANNED', 'APPROACHING');

  if v_stop.kind = 'PICKUP' then
    update public.bookings set status = 'ARRIVED'
    where id = v_stop.booking_id
      and status in ('CONFIRMED', 'DRIVER_ASSIGNED', 'APPROACHING');

    insert into public.trip_events (company_id, trip_id, booking_id, type, idempotency_key, created_by)
    values (v_stop.company_id, v_stop.trip_id, v_stop.booking_id, 'ARRIVED_AT_PICKUP',
            'arrived:' || p_stop_id, auth.uid())
    on conflict (company_id, idempotency_key) do nothing;
  end if;
end;
$$;

-- ---------- drepturi de execuție ----------
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;

grant execute on function
  public.is_platform_admin(),
  public.company_role(uuid),
  public.is_company_member(uuid),
  public.is_company_staff(uuid),
  public.is_company_admin(uuid),
  public.is_trip_driver(uuid),
  public.has_feature(uuid, text),
  public.company_can_write(uuid),
  public.free_seats(uuid, int, int),
  public.book_seats(uuid, uuid, int, int, int, text, double precision, double precision, text,
                    text, double precision, double precision, int, text, public.payment_method,
                    boolean, int, text),
  public.confirm_booking(uuid),
  public.cancel_booking(uuid, text),
  public.find_matching_trips(double precision, double precision, double precision,
                             double precision, int, timestamptz, timestamptz, double precision),
  public.ingest_position(uuid, double precision, double precision, timestamptz, real, real, uuid),
  public.mark_stop_arrived(uuid)
to authenticated;
