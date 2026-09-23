-- 1500 — Link de urmărire pentru client, lista de pasageri, exportul rezervărilor
--
-- Link de urmărire: clientul nu are cont. Primește prin SMS/WhatsApp un link cu un token
-- lung (43 de caractere, 256 de biți); în bază se păstrează doar hash-ul. get_tracking e
-- singura funcție apelabilă de vizitatori anonimi și întoarce doar ce are voie clientul
-- să vadă (ADR-0004):
--   * numele șoferului (doar prenumele), vehiculul și numărul — de la 24 h înainte de plecare;
--   * poziția exactă a vehiculului — doar în cursă, când clientul e la bord sau când
--     microbuzul e aproape (cel mult 3 opriri înainte sau ETA sub 90 de minute).
--
-- Coduri de eroare noi: FEATURE_NOT_ENABLED.

create table public.booking_tracking_tokens (
  booking_id  uuid primary key,
  company_id  uuid not null,
  token_hash  text not null unique,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  foreign key (booking_id, company_id) references public.bookings (id, company_id) on delete cascade
);
alter table public.booking_tracking_tokens enable row level security;
-- Nicio politică: tabelul e accesat doar prin funcțiile de mai jos.
revoke all on public.booking_tracking_tokens from authenticated, anon;

create or replace function public._token_hash(p_token text)
returns text
language sql immutable
as $$
  select encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex');
$$;

create or replace function public.create_tracking_link(p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company   uuid;
  v_departure timestamptz;
  v_token     text;
begin
  select b.company_id, t.departure_at into v_company, v_departure
  from public.bookings b join public.trips t on t.id = b.trip_id
  where b.id = p_booking_id;
  if v_company is null or not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not public.has_feature(v_company, 'tracking_link') then
    raise exception 'FEATURE_NOT_ENABLED' using errcode = '42501';
  end if;

  v_token := rtrim(translate(encode(uuid_send(gen_random_uuid()) || uuid_send(gen_random_uuid()), 'base64'),
                             '+/', '-_'), '=');

  insert into public.booking_tracking_tokens (booking_id, company_id, token_hash, expires_at)
  values (p_booking_id, v_company, public._token_hash(v_token), v_departure + interval '3 days')
  on conflict (booking_id) do update
    set token_hash = excluded.token_hash, created_at = now(), expires_at = excluded.expires_at;

  return v_token;
end;
$$;

create or replace function public.get_tracking(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_booking       public.bookings%rowtype;
  v_trip          public.trips%rowtype;
  v_pickup        public.trip_stops%rowtype;
  v_company_name  text;
  v_stops_before  int;
  v_eta           timestamptz;
  v_show_details  boolean;
  v_show_position boolean;
  v_driver        text;
  v_vehicle       jsonb;
  v_position      jsonb;
begin
  if coalesce(length(p_token), 0) < 40 then
    return null;
  end if;

  select b.* into v_booking
  from public.booking_tracking_tokens tt
  join public.bookings b on b.id = tt.booking_id
  where tt.token_hash = public._token_hash(p_token) and tt.expires_at > now();
  if v_booking.id is null or not public.has_feature(v_booking.company_id, 'tracking_link') then
    return null;
  end if;

  select * into v_trip from public.trips where id = v_booking.trip_id;
  select name into v_company_name from public.companies where id = v_booking.company_id;
  select * into v_pickup from public.trip_stops where booking_id = v_booking.id and kind = 'PICKUP';

  select count(*)::int into v_stops_before
  from public.trip_stops s
  where s.trip_id = v_trip.id and s.seq < v_pickup.seq
    and s.status in ('PLANNED', 'APPROACHING', 'ARRIVED');

  v_eta := coalesce(v_pickup.eta_at, v_pickup.planned_at);

  v_show_details := v_booking.status not in ('CANCELLED', 'NO_SHOW', 'COMPLETED', 'HELD', 'REQUESTED')
                    and (v_trip.status = 'IN_PROGRESS' or v_trip.departure_at < now() + interval '24 hours');

  v_show_position := v_trip.status = 'IN_PROGRESS'
    and (v_booking.status = 'ON_BOARD'
         or (v_booking.status in ('CONFIRMED', 'DRIVER_ASSIGNED', 'APPROACHING', 'ARRIVED')
             and (v_stops_before <= 3 or (v_eta is not null and v_eta < now() + interval '90 minutes'))));

  if v_show_details then
    select split_part(d.full_name, ' ', 1) into v_driver from public.drivers d where d.id = v_trip.driver_id;
    select jsonb_build_object('label', v.label, 'plate', v.plate, 'seats', v.seats)
      into v_vehicle from public.vehicles v where v.id = v_trip.vehicle_id;
  end if;

  if v_show_position then
    select jsonb_build_object('lat', st_y(p.location::geometry), 'lng', st_x(p.location::geometry),
                              'heading', p.heading_deg, 'recorded_at', p.recorded_at)
      into v_position
    from public.vehicle_positions_current p
    where p.vehicle_id = v_trip.vehicle_id and p.recorded_at > now() - interval '10 minutes';
  end if;

  return jsonb_build_object(
    'company', v_company_name,
    'booking_status', v_booking.status,
    'passengers', v_booking.passengers,
    'trip_title', v_trip.title,
    'trip_status', v_trip.status,
    'departure_at', v_trip.departure_at,
    'pickup', jsonb_build_object(
      'address', v_pickup.address,
      'notes', v_booking.pickup_notes,
      'planned_at', v_pickup.planned_at,
      'eta_at', v_pickup.eta_at,
      'status', v_pickup.status,
      'lat', st_y(v_pickup.location::geometry),
      'lng', st_x(v_pickup.location::geometry)
    ),
    'stops_before', case when v_pickup.status in ('DONE', 'SKIPPED') then 0 else v_stops_before end,
    'driver_first_name', v_driver,
    'vehicle', v_vehicle,
    'vehicle_position', v_position,
    'locale', (select locale from public.customers where id = v_booking.customer_id)
  );
end;
$$;

-- ---------- lista de pasageri (pentru PDF-ul de la plecare) ----------

create or replace function public.get_passenger_manifest(p_trip_id uuid)
returns table (
  booking_id      uuid,
  pickup_seq      int,
  full_name       text,
  phone           text,
  passengers      int,
  seats           int[],
  from_name       text,
  to_name         text,
  pickup_address  text,
  pickup_notes    text,
  luggage_notes   text,
  payment_method  public.payment_method,
  price_cents     int,
  currency        text,
  status          public.booking_status
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require_trip_actor(p_trip_id);
  return query
  select b.id, ps.seq, c.full_name, c.phone, b.passengers,
         (select array_agg(bs.seat_no order by bs.seat_no) from public.booking_seats bs where bs.booking_id = b.id),
         fp.name, tp.name, b.pickup_address, b.pickup_notes, b.luggage_notes,
         b.payment_method, b.price_cents, b.currency, b.status
  from public.bookings b
  join public.customers c on c.id = b.customer_id
  join public.trip_route_points fp on fp.trip_id = b.trip_id and fp.seq = b.from_seq
  join public.trip_route_points tp on tp.trip_id = b.trip_id and tp.seq = b.to_seq
  left join public.trip_stops ps on ps.booking_id = b.id and ps.kind = 'PICKUP'
  where b.trip_id = p_trip_id and b.status not in ('CANCELLED', 'NO_SHOW', 'HELD', 'REQUESTED')
  order by ps.seq nulls last, c.full_name;
end;
$$;

-- ---------- export rezervări pentru contabilitate ----------

create or replace function public.export_bookings(p_company_id uuid, p_from timestamptz, p_to timestamptz)
returns table (
  departure_at    timestamptz,
  trip_title      text,
  vehicle_label   text,
  booking_id      uuid,
  customer_name   text,
  customer_phone  text,
  passengers      int,
  from_name       text,
  to_name         text,
  price_cents     int,
  currency        text,
  payment_method  public.payment_method,
  status          public.booking_status,
  created_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_company_staff(p_company_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not public.has_feature(p_company_id, 'bookings_export') then
    raise exception 'FEATURE_NOT_ENABLED' using errcode = '42501';
  end if;

  return query
  select t.departure_at, t.title, v.label, b.id, c.full_name, c.phone, b.passengers,
         fp.name, tp.name, b.price_cents, b.currency, b.payment_method, b.status, b.created_at
  from public.bookings b
  join public.trips t     on t.id = b.trip_id
  join public.vehicles v  on v.id = t.vehicle_id
  join public.customers c on c.id = b.customer_id
  join public.trip_route_points fp on fp.trip_id = b.trip_id and fp.seq = b.from_seq
  join public.trip_route_points tp on tp.trip_id = b.trip_id and tp.seq = b.to_seq
  where b.company_id = p_company_id
    and t.departure_at >= p_from and t.departure_at < p_to
    and b.status not in ('HELD', 'REQUESTED')
  order by t.departure_at, t.title, c.full_name;
end;
$$;

revoke execute on function public._token_hash(text) from public, anon, authenticated;
revoke execute on function public.create_tracking_link(uuid), public.get_passenger_manifest(uuid),
  public.export_bookings(uuid, timestamptz, timestamptz), public.get_tracking(text) from public;
grant execute on function public.create_tracking_link(uuid), public.get_passenger_manifest(uuid),
  public.export_bookings(uuid, timestamptz, timestamptz) to authenticated;
revoke execute on function public.create_tracking_link(uuid), public.get_passenger_manifest(uuid),
  public.export_bookings(uuid, timestamptz, timestamptz) from anon;
-- Singura funcție pentru vizitatori anonimi:
grant execute on function public.get_tracking(text) to anon, authenticated;
