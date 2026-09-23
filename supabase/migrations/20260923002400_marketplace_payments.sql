-- 2400 — Marketplace pentru clienți, conturi de client, prețuri pe porțiuni, plăți direct la firmă
--        (ADR-0009)
--
-- * Căutarea publică (search_marketplace): toate firmele active, cu microbuze aprobate, ordonate
--   neutru după ora plecării și distanța față de client. Nicio firmă nu plătește pentru poziție.
-- * Clientul are cont (client_profiles) și rezervă direct la firma aleasă (book_marketplace).
-- * Prețuri pe porțiuni de rută, setate de firmă (route_template_prices), pe persoană.
-- * Plăți: integral sau avans online (Stripe Connect Standard, în contul firmei, fără comision),
--   sau numerar la șofer; restul se încasează la destinație (record_cash_payment).
-- * Fără colaborare între firme: fiecare firmă transportă doar cu microbuzele ei aprobate.
--   Clientul vede dacă firma are vehicul de rezervă.
--
-- Coduri de eroare noi: PROFILE_REQUIRED, PAYMENT_OPTION_NOT_AVAILABLE, PRICE_NOT_SET,
-- PHONE_NOT_VERIFIED, CANCELLATION_TOO_LATE, PAYMENT_MISMATCH.

insert into public.features (key, description) values
  ('marketplace_listing', 'Apariție în căutarea publică și rezervări online de la clienți');
insert into public.plan_features (plan_id, feature_key)
select id, 'marketplace_listing' from public.plans where id in ('START', 'PRO', 'PILOT');

-- ---------- setările de plată ale firmei ----------

create table public.company_payment_settings (
  company_id              uuid primary key references public.companies (id) on delete cascade,
  accepts_full            boolean not null default true,
  accepts_deposit         boolean not null default true,
  deposit_percent         int not null default 20 check (deposit_percent between 5 and 100),
  accepts_cash            boolean not null default true,
  cancel_until_hours      int not null default 24 check (cancel_until_hours between 0 and 720),
  stripe_account_id       text unique,
  stripe_charges_enabled  boolean not null default false,
  updated_at              timestamptz not null default now()
);
alter table public.company_payment_settings enable row level security;
create policy payment_settings_select on public.company_payment_settings for select to authenticated
  using (public.is_company_staff(company_id));
create policy payment_settings_write on public.company_payment_settings for all to authenticated
  using (public.is_company_admin(company_id)) with check (public.is_company_admin(company_id));
-- Contul Stripe îl scrie doar webhook-ul (service_role), după confirmarea de la Stripe.
grant select on public.company_payment_settings to authenticated;
grant insert (company_id, accepts_full, accepts_deposit, deposit_percent, accepts_cash, cancel_until_hours)
  on public.company_payment_settings to authenticated;
grant update (accepts_full, accepts_deposit, deposit_percent, accepts_cash, cancel_until_hours, updated_at)
  on public.company_payment_settings to authenticated;

-- ---------- prețuri pe porțiuni (pe persoană) ----------

create table public.route_template_prices (
  template_id  uuid not null,
  company_id   uuid not null,
  from_seq     int not null check (from_seq >= 0),
  to_seq       int not null,
  price_cents  int not null check (price_cents > 0),
  currency     text not null default 'EUR' check (currency in ('EUR', 'RON')),
  primary key (template_id, from_seq, to_seq),
  check (to_seq > from_seq),
  foreign key (template_id, company_id) references public.route_templates (id, company_id) on delete cascade
);
alter table public.route_template_prices enable row level security;
create policy route_prices_select on public.route_template_prices for select to authenticated
  using (public.is_company_staff(company_id));
create policy route_prices_write on public.route_template_prices for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_write(company_id));
grant select, insert, update, delete on public.route_template_prices to authenticated;

alter table public.trips add column template_id uuid;
alter table public.trips add constraint trips_template_fk
  foreign key (template_id, company_id) references public.route_templates (id, company_id) on delete set null (template_id);

create or replace function public._trip_price_cents(p_trip_id uuid, p_from_seq int, p_to_seq int)
returns table (price_cents int, currency text)
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select p.price_cents, p.currency
  from public.trips t
  join public.route_template_prices p on p.template_id = t.template_id
  where t.id = p_trip_id and p.from_seq = p_from_seq and p.to_seq = p_to_seq;
$$;

-- Cursa din șablon păstrează legătura cu șablonul (pentru prețuri).
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

  insert into public.trips (company_id, vehicle_id, driver_id, title, departure_at, template_id)
  values (v_company, p_vehicle_id, p_driver_id, coalesce(nullif(trim(p_title), ''), v_title), p_departure_at, p_template_id)
  returning id into v_trip;

  insert into public.trip_route_points (trip_id, company_id, seq, name, location)
  select v_trip, v_company, rtp.seq, pl.name, pl.location
  from public.route_template_points rtp
  join public.places pl on pl.id = rtp.place_id
  where rtp.template_id = p_template_id;

  return v_trip;
end;
$$;

-- ---------- conturi de client ----------

create table public.client_profiles (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null check (length(trim(full_name)) between 2 and 120),
  phone       text not null check (phone ~ '^\+?[0-9]{6,20}$'),
  locale      text not null default 'ro' check (locale in ('ro', 'de', 'en')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.client_profiles enable row level security;
create policy client_profiles_self on public.client_profiles for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.client_profiles to authenticated;

-- Fișa de client a firmei poate fi legată de contul clientului.
alter table public.customers add column user_id uuid references auth.users (id) on delete set null;
create index customers_user_idx on public.customers (user_id);

create or replace function public.is_booking_client(p_booking uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.bookings b join public.customers c on c.id = b.customer_id
    where b.id = p_booking and c.user_id = auth.uid() and auth.uid() is not null
  );
$$;

drop policy customers_select on public.customers;
create policy customers_select on public.customers for select to authenticated
  using (
    public.is_company_staff(company_id)
    or (user_id is not null and user_id = auth.uid())
    or exists (select 1 from public.bookings b
               where b.customer_id = customers.id and public.is_trip_driver(b.trip_id))
  );
drop policy bookings_select on public.bookings;
create policy bookings_select on public.bookings for select to authenticated
  using (public.is_company_staff(company_id) or public.is_trip_driver(trip_id) or public.is_booking_client(id));

-- ---------- rezervări: sursă și plăți ----------

alter table public.bookings
  add column source text not null default 'DISPATCH' check (source in ('DISPATCH', 'MARKETPLACE', 'SITE')),
  add column amount_paid_cents int not null default 0 check (amount_paid_cents >= 0),
  add column payment_status text not null default 'UNPAID'
    check (payment_status in ('UNPAID', 'DEPOSIT_PAID', 'PAID', 'REFUNDED'));

create table public.payments (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null,
  booking_id    uuid not null,
  kind          text not null check (kind in ('FULL', 'DEPOSIT', 'REMAINDER')),
  method        text not null check (method in ('STRIPE', 'CASH')),
  amount_cents  int not null check (amount_cents > 0),
  currency      text not null default 'EUR' check (currency in ('EUR', 'RON')),
  status        text not null default 'PENDING' check (status in ('PENDING', 'PAID', 'EXPIRED', 'FAILED', 'REFUNDED')),
  provider_ref  text,
  late          boolean not null default false,
  created_by    uuid,
  created_at    timestamptz not null default now(),
  paid_at       timestamptz,
  unique (method, provider_ref),
  foreign key (booking_id, company_id) references public.bookings (id, company_id) on delete cascade
);
create index payments_booking_idx on public.payments (booking_id);
alter table public.payments enable row level security;
create policy payments_select on public.payments for select to authenticated
  using (public.is_company_staff(company_id) or public.is_booking_client(booking_id));
grant select on public.payments to authenticated;
revoke insert, update, delete on public.payments from authenticated;

-- Totalul încasat al unei rezervări, recalculat din plăți.
create or replace function public._refresh_booking_payment(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_paid  int;
  v_price int;
begin
  select coalesce(sum(amount_cents), 0)::int into v_paid
  from public.payments where booking_id = p_booking_id and status = 'PAID';
  select price_cents into v_price from public.bookings where id = p_booking_id;
  update public.bookings
  set amount_paid_cents = v_paid,
      payment_status = case when v_paid = 0 then 'UNPAID'
                            when v_price is not null and v_paid >= v_price then 'PAID'
                            else 'DEPOSIT_PAID' end
  where id = p_booking_id;
end;
$$;

-- ---------- nucleul comun al rezervării (dispecer și marketplace) ----------
-- Presupune: rândul cursei e blocat de apelant, drepturile și segmentul sunt verificate.
create or replace function public._create_booking_core(
  p_company uuid, p_trip_id uuid, p_customer_id uuid, p_passengers int, p_from_seq int, p_to_seq int,
  p_pickup_address text, p_pickup_lat double precision, p_pickup_lng double precision, p_pickup_notes text,
  p_dropoff_address text, p_dropoff_lat double precision, p_dropoff_lng double precision,
  p_price_cents int, p_currency text, p_payment_method public.payment_method,
  p_confirm boolean, p_hold_minutes int, p_idempotency_key text, p_source text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_seats   int;
  v_free    int[];
  v_booking uuid;
  v_range   int4range := int4range(p_from_seq, p_to_seq);
begin
  select v.seats into v_seats
  from public.trips t join public.vehicles v on v.id = t.vehicle_id and v.company_id = t.company_id
  where t.id = p_trip_id;

  perform public._release_expired_holds(p_trip_id);

  select array_agg(s order by s) into v_free
  from (
    select s
    from generate_series(1, v_seats) as s
    where not exists (
      select 1 from public.booking_seats bs
      where bs.trip_id = p_trip_id and bs.seat_no = s and bs.released_at is null and bs.segment && v_range
    )
    order by s
    limit p_passengers
  ) free;

  if coalesce(array_length(v_free, 1), 0) < p_passengers then
    raise exception 'NOT_ENOUGH_SEATS' using errcode = 'P0001',
      detail = format('available=%s', coalesce(array_length(v_free, 1), 0));
  end if;

  insert into public.bookings (
    company_id, trip_id, customer_id, status, passengers, from_seq, to_seq,
    pickup_address, pickup_location, pickup_notes, dropoff_address, dropoff_location,
    price_cents, currency, payment_method, hold_expires_at, idempotency_key, created_by, source
  ) values (
    p_company, p_trip_id, p_customer_id,
    case when p_confirm then 'CONFIRMED' else 'HELD' end::public.booking_status,
    p_passengers, p_from_seq, p_to_seq,
    p_pickup_address,
    case when p_pickup_lat is not null and p_pickup_lng is not null
         then st_setsrid(st_makepoint(p_pickup_lng, p_pickup_lat), 4326)::geography end,
    p_pickup_notes,
    p_dropoff_address,
    case when p_dropoff_lat is not null and p_dropoff_lng is not null
         then st_setsrid(st_makepoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography end,
    p_price_cents, coalesce(p_currency, 'EUR'), p_payment_method,
    case when p_confirm then null else now() + make_interval(mins => greatest(p_hold_minutes, 1)) end,
    p_idempotency_key, auth.uid(), p_source
  )
  returning id into v_booking;

  insert into public.booking_seats (booking_id, company_id, trip_id, seat_no, segment)
  select v_booking, p_company, p_trip_id, s, v_range from unnest(v_free) as s;

  return v_booking;
end;
$$;

-- book_seats (dispecer): aceleași verificări ca înainte, locurile prin nucleul comun.
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
  v_max_seq   int;
  v_existing  uuid;
begin
  select t.company_id, t.status into v_company, v_status
  from public.trips t where t.id = p_trip_id for update of t;

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

  if p_idempotency_key is not null then
    select id into v_existing from public.bookings
    where company_id = v_company and idempotency_key = p_idempotency_key;
    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  select max(seq) into v_max_seq from public.trip_route_points where trip_id = p_trip_id;
  if v_max_seq is null or p_from_seq < 0 or p_to_seq > v_max_seq or p_to_seq <= p_from_seq then
    raise exception 'INVALID_SEGMENT' using errcode = '22023';
  end if;
  if p_passengers is null or p_passengers < 1 then
    raise exception 'INVALID_SEGMENT' using errcode = '22023', detail = 'passengers';
  end if;

  return public._create_booking_core(
    v_company, p_trip_id, p_customer_id, p_passengers, p_from_seq, p_to_seq,
    p_pickup_address, p_pickup_lat, p_pickup_lng, p_pickup_notes,
    p_dropoff_address, p_dropoff_lat, p_dropoff_lng,
    p_price_cents, p_currency, p_payment_method, p_confirm, p_hold_minutes, p_idempotency_key, 'DISPATCH');
end;
$$;

-- ---------- căutarea publică ----------

create or replace function public.search_marketplace(
  p_pickup_lat      double precision,
  p_pickup_lng      double precision,
  p_dropoff_lat     double precision,
  p_dropoff_lng     double precision,
  p_passengers      int,
  p_window_start    timestamptz,
  p_window_end      timestamptz,
  p_max_distance_m  double precision default 30000
)
returns table (
  trip_id              uuid,
  company_name         text,
  company_slug         text,
  departure_at         timestamptz,
  from_seq             int,
  from_name            text,
  to_seq               int,
  to_name              text,
  free_seats           int,
  price_cents          int,
  currency             text,
  vehicle              jsonb,
  has_backup_vehicle   boolean,
  accepts_full         boolean,
  accepts_deposit      boolean,
  deposit_percent      int,
  accepts_cash         boolean,
  online_payment       boolean,
  cancel_until_hours   int,
  pickup_distance_m    double precision
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  with pts as (
    select st_setsrid(st_makepoint(p_pickup_lng, p_pickup_lat), 4326)::geography   as pickup,
           st_setsrid(st_makepoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography as dropoff
  ),
  candidates as (
    select t.id, t.company_id, t.departure_at, t.vehicle_id, st_distance(t.route_line, pts.pickup) as pickup_d
    from public.trips t
    join public.companies c on c.id = t.company_id and c.status = 'ACTIVE'
    join public.vehicles v  on v.id = t.vehicle_id and v.approval_status = 'APPROVED'
    cross join pts
    where t.status = 'PLANNED'
      and t.departure_at between greatest(p_window_start, now() + interval '30 minutes') and p_window_end
      and t.route_line is not null
      and st_dwithin(t.route_line, pts.pickup,  p_max_distance_m)
      and st_dwithin(t.route_line, pts.dropoff, p_max_distance_m)
      and public.has_feature(t.company_id, 'marketplace_listing')
  ),
  with_seq as (
    select c.*,
      (select rp.seq from public.trip_route_points rp, pts
        where rp.trip_id = c.id order by rp.location <-> pts.pickup, rp.seq limit 1) as f_seq,
      (select rp.seq from public.trip_route_points rp, pts
        where rp.trip_id = c.id order by rp.location <-> pts.dropoff, rp.seq desc limit 1) as t_seq
    from candidates c
  ),
  seats as (
    select w.*, (select v.seats from public.vehicles v where v.id = w.vehicle_id)
                - (select count(distinct bs.seat_no) from public.booking_seats bs
                   join public.bookings b on b.id = bs.booking_id
                   where bs.trip_id = w.id and bs.released_at is null
                     and bs.segment && int4range(w.f_seq, w.t_seq)
                     and not (b.status = 'HELD' and b.hold_expires_at < now()))::int as free
    from with_seq w
    where w.f_seq < w.t_seq
  )
  select s.id, co.name, co.slug, s.departure_at,
         s.f_seq, fp.name, s.t_seq, tp.name, s.free,
         pr.price_cents, coalesce(pr.currency, 'EUR'),
         public._vehicle_public(s.vehicle_id),
         exists (select 1 from public.vehicles v where v.company_id = s.company_id
                 and v.is_standby and v.approval_status = 'APPROVED'),
         coalesce(ps.accepts_full, true), coalesce(ps.accepts_deposit, true), coalesce(ps.deposit_percent, 20),
         coalesce(ps.accepts_cash, true), coalesce(ps.stripe_charges_enabled, false),
         coalesce(ps.cancel_until_hours, 24), s.pickup_d
  from seats s
  join public.companies co on co.id = s.company_id
  join public.trip_route_points fp on fp.trip_id = s.id and fp.seq = s.f_seq
  join public.trip_route_points tp on tp.trip_id = s.id and tp.seq = s.t_seq
  left join lateral public._trip_price_cents(s.id, s.f_seq, s.t_seq) pr on true
  left join public.company_payment_settings ps on ps.company_id = s.company_id
  where s.free >= greatest(p_passengers, 1)
  order by s.departure_at, s.pickup_d
  limit 50;
$$;

-- Oferta unei singure curse (pagina de rezervare), cu aceleași reguli ca în căutare.
create or replace function public.get_marketplace_offer(p_trip_id uuid, p_from_seq int, p_to_seq int, p_passengers int)
returns table (
  trip_id uuid, company_name text, company_slug text, departure_at timestamptz,
  from_name text, to_name text, free_seats int, price_cents int, currency text, vehicle jsonb,
  has_backup_vehicle boolean, accepts_full boolean, accepts_deposit boolean, deposit_percent int,
  accepts_cash boolean, online_payment boolean, cancel_until_hours int
)
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select t.id, co.name, co.slug, t.departure_at, fp.name, tp.name,
         v.seats - (select count(distinct bs.seat_no) from public.booking_seats bs
                    join public.bookings b on b.id = bs.booking_id
                    where bs.trip_id = t.id and bs.released_at is null
                      and bs.segment && int4range(p_from_seq, p_to_seq)
                      and not (b.status = 'HELD' and b.hold_expires_at < now()))::int,
         pr.price_cents, coalesce(pr.currency, 'EUR'), public._vehicle_public(v.id),
         exists (select 1 from public.vehicles x where x.company_id = t.company_id and x.is_standby and x.approval_status = 'APPROVED'),
         coalesce(ps.accepts_full, true), coalesce(ps.accepts_deposit, true), coalesce(ps.deposit_percent, 20),
         coalesce(ps.accepts_cash, true), coalesce(ps.stripe_charges_enabled, false), coalesce(ps.cancel_until_hours, 24)
  from public.trips t
  join public.companies co on co.id = t.company_id and co.status = 'ACTIVE'
  join public.vehicles v on v.id = t.vehicle_id and v.approval_status = 'APPROVED'
  join public.trip_route_points fp on fp.trip_id = t.id and fp.seq = p_from_seq
  join public.trip_route_points tp on tp.trip_id = t.id and tp.seq = p_to_seq
  left join lateral public._trip_price_cents(t.id, p_from_seq, p_to_seq) pr on true
  left join public.company_payment_settings ps on ps.company_id = t.company_id
  where t.id = p_trip_id and t.status = 'PLANNED' and t.departure_at > now() + interval '30 minutes'
    and p_to_seq > p_from_seq and public.has_feature(t.company_id, 'marketplace_listing');
$$;

-- Lista de orașe e publică (pentru căutare), cu coordonate ca numere.
create policy places_read_anon on public.places for select to anon using (true);
grant select on public.places to anon;

create or replace function public.public_places()
returns table (id uuid, name text, country char(2), lat double precision, lng double precision)
language sql stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  select p.id, p.name, p.country, st_y(p.location::geometry), st_x(p.location::geometry)
  from public.places p order by p.country, p.name;
$$;
revoke execute on function public.public_places() from public;
grant execute on function public.public_places() to anon, authenticated;

-- ---------- rezervarea clientului ----------

create or replace function public.book_marketplace(
  p_trip_id          uuid,
  p_from_seq         int,
  p_to_seq           int,
  p_passengers       int,
  p_pickup_address   text,
  p_pickup_notes     text,
  p_payment          text,
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile   public.client_profiles%rowtype;
  v_trip      public.trips%rowtype;
  v_settings  public.company_payment_settings%rowtype;
  v_customer  public.customers%rowtype;
  v_price     int;
  v_currency  text;
  v_total     int;
  v_due       int;
  v_booking   uuid;
  v_payment   uuid;
  v_verified  boolean;
  v_max_seq   int;
begin
  if auth.uid() is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select * into v_profile from public.client_profiles where user_id = auth.uid();
  if v_profile.user_id is null then
    raise exception 'PROFILE_REQUIRED' using errcode = '22023';
  end if;
  if p_payment not in ('FULL', 'DEPOSIT', 'CASH') or coalesce(length(p_idempotency_key), 0) < 8 then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  select * into v_trip from public.trips where id = p_trip_id for update;
  if v_trip.id is null then
    raise exception 'TRIP_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Idempotență: aceeași cheie de la același client întoarce aceeași rezervare.
  select b.id into v_booking from public.bookings b join public.customers c on c.id = b.customer_id
  where b.company_id = v_trip.company_id and b.idempotency_key = p_idempotency_key and c.user_id = auth.uid();
  if v_booking is not null then
    select id into v_payment from public.payments where booking_id = v_booking order by created_at desc limit 1;
    return jsonb_build_object('booking_id', v_booking, 'payment_id', v_payment, 'repeated', true);
  end if;

  if v_trip.status <> 'PLANNED' or v_trip.departure_at < now() + interval '30 minutes'
     or not exists (select 1 from public.companies where id = v_trip.company_id and status = 'ACTIVE')
     or not public.has_feature(v_trip.company_id, 'marketplace_listing') then
    raise exception 'TRIP_CLOSED' using errcode = '22023';
  end if;
  if (select approval_status from public.vehicles where id = v_trip.vehicle_id) <> 'APPROVED' then
    raise exception 'VEHICLE_NOT_APPROVED' using errcode = '22023';
  end if;
  select max(seq) into v_max_seq from public.trip_route_points where trip_id = p_trip_id;
  if v_max_seq is null or p_from_seq < 0 or p_to_seq > v_max_seq or p_to_seq <= p_from_seq
     or coalesce(p_passengers, 0) not between 1 and 20 then
    raise exception 'INVALID_SEGMENT' using errcode = '22023';
  end if;

  -- Opțiunea de plată trebuie acceptată de firmă; online doar cu Stripe conectat și preț setat.
  select * into v_settings from public.company_payment_settings where company_id = v_trip.company_id;
  if (p_payment = 'FULL' and not coalesce(v_settings.accepts_full, true))
     or (p_payment = 'DEPOSIT' and not coalesce(v_settings.accepts_deposit, true))
     or (p_payment = 'CASH' and not coalesce(v_settings.accepts_cash, true))
     or (p_payment in ('FULL', 'DEPOSIT') and not coalesce(v_settings.stripe_charges_enabled, false)) then
    raise exception 'PAYMENT_OPTION_NOT_AVAILABLE' using errcode = '22023';
  end if;
  select price_cents, currency into v_price, v_currency from public._trip_price_cents(p_trip_id, p_from_seq, p_to_seq);
  if p_payment in ('FULL', 'DEPOSIT') and v_price is null then
    raise exception 'PRICE_NOT_SET' using errcode = '22023';
  end if;
  v_total := v_price * p_passengers;

  -- Fișa de client a firmei: legată de cont. O fișă existentă, fără cont, se leagă doar dacă
  -- telefonul contului e confirmat (altfel oricine ar vedea istoricul altcuiva).
  select * into v_customer from public.customers where company_id = v_trip.company_id and phone = v_profile.phone;
  if v_customer.id is null then
    insert into public.customers (company_id, full_name, phone, locale, user_id)
    values (v_trip.company_id, v_profile.full_name, v_profile.phone, v_profile.locale, auth.uid())
    returning * into v_customer;
  elsif v_customer.user_id is distinct from auth.uid() then
    select exists (select 1 from auth.users u where u.id = auth.uid()
                   and regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = regexp_replace(v_profile.phone, '[^0-9]', '', 'g')
                   and u.phone_confirmed_at is not null) into v_verified;
    if v_customer.user_id is not null or not v_verified then
      raise exception 'PHONE_NOT_VERIFIED' using errcode = '42501';
    end if;
    update public.customers set user_id = auth.uid() where id = v_customer.id;
  end if;

  v_booking := public._create_booking_core(
    v_trip.company_id, p_trip_id, v_customer.id, p_passengers, p_from_seq, p_to_seq,
    left(trim(coalesce(p_pickup_address, '')), 300), null, null, nullif(left(trim(coalesce(p_pickup_notes, '')), 500), ''),
    null, null, null,
    v_total, coalesce(v_currency, 'EUR'),
    case p_payment when 'FULL' then 'CARD' when 'DEPOSIT' then 'DEPOSIT_AND_REST' else 'CASH_TO_DRIVER' end::public.payment_method,
    p_payment = 'CASH',
    35,  -- locul e ținut cât clientul plătește (sesiunea Stripe expiră în 30 de minute)
    p_idempotency_key, 'MARKETPLACE');

  if p_payment in ('FULL', 'DEPOSIT') then
    v_due := case when p_payment = 'FULL' then v_total
                  else greatest(ceil(v_total * v_settings.deposit_percent / 100.0)::int, 1) end;
    insert into public.payments (company_id, booking_id, kind, method, amount_cents, currency, created_by)
    values (v_trip.company_id, v_booking, p_payment, 'STRIPE', v_due, coalesce(v_currency, 'EUR'), auth.uid())
    returning id into v_payment;
  end if;

  return jsonb_build_object('booking_id', v_booking, 'payment_id', v_payment, 'amount_due_now_cents', v_due,
                            'total_cents', v_total, 'currency', coalesce(v_currency, 'EUR'),
                            'stripe_account_id', case when v_payment is not null then v_settings.stripe_account_id end,
                            'repeated', false);
end;
$$;

-- Serverul aplicației atașează sesiunea Stripe creată pentru plată (o singură dată).
create or replace function public.attach_payment_session(p_payment_id uuid, p_session_id text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_booking uuid;
begin
  select booking_id into v_booking from public.payments where id = p_payment_id and status = 'PENDING' and provider_ref is null;
  if v_booking is null or not public.is_booking_client(v_booking) or coalesce(length(p_session_id), 0) < 10 then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.payments set provider_ref = p_session_id where id = p_payment_id;
end;
$$;

-- ---------- webhook Stripe (service_role) ----------

create or replace function public.mark_payment_paid(p_provider_ref text, p_amount_cents int)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment public.payments%rowtype;
  v_status  public.booking_status;
begin
  select * into v_payment from public.payments where method = 'STRIPE' and provider_ref = p_provider_ref for update;
  if v_payment.id is null then
    raise exception 'BOOKING_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_payment.status = 'PAID' then
    return 'ALREADY_PAID';
  end if;
  if p_amount_cents is distinct from v_payment.amount_cents then
    raise exception 'PAYMENT_MISMATCH' using errcode = '22023';
  end if;

  perform 1 from public.trips t join public.bookings b on b.trip_id = t.id where b.id = v_payment.booking_id for update of t;
  select status into v_status from public.bookings where id = v_payment.booking_id;

  update public.payments
  set status = 'PAID', paid_at = now(), late = v_status = 'CANCELLED'
  where id = v_payment.id;
  perform public._refresh_booking_payment(v_payment.booking_id);

  if v_status = 'HELD' then
    update public.bookings set status = 'CONFIRMED', hold_expires_at = null where id = v_payment.booking_id;
    return 'CONFIRMED';
  end if;
  -- Plată sosită după expirarea rezervării: banii sunt la firmă, care rambursează (plata e marcată „late”).
  return case when v_status = 'CANCELLED' then 'LATE_PAYMENT' else 'PAID' end;
end;
$$;

create or replace function public.mark_payment_expired(p_provider_ref text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment public.payments%rowtype;
begin
  select * into v_payment from public.payments where method = 'STRIPE' and provider_ref = p_provider_ref for update;
  if v_payment.id is null or v_payment.status <> 'PENDING' then
    return;
  end if;
  update public.payments set status = 'EXPIRED' where id = v_payment.id;
  update public.bookings set status = 'CANCELLED', cancel_reason = 'PAYMENT_EXPIRED', hold_expires_at = null
  where id = v_payment.booking_id and status = 'HELD';
  update public.booking_seats set released_at = now()
  where booking_id = v_payment.booking_id and released_at is null
    and (select status from public.bookings where id = v_payment.booking_id) = 'CANCELLED';
end;
$$;

create or replace function public.mark_payment_refunded(p_provider_ref text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_booking uuid;
begin
  update public.payments set status = 'REFUNDED'
  where method = 'STRIPE' and provider_ref = p_provider_ref and status = 'PAID'
  returning booking_id into v_booking;
  if v_booking is not null then
    perform public._refresh_booking_payment(v_booking);
    update public.bookings set payment_status = 'REFUNDED'
    where id = v_booking and amount_paid_cents = 0
      and exists (select 1 from public.payments where booking_id = v_booking and status = 'REFUNDED');
  end if;
end;
$$;

-- Contul Stripe al firmei, confirmat de Stripe prin webhook (metadata.company_id).
create or replace function public.set_company_stripe_account(p_company_id uuid, p_account_id text, p_charges_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_account_id !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;
  insert into public.company_payment_settings (company_id, stripe_account_id, stripe_charges_enabled)
  values (p_company_id, p_account_id, p_charges_enabled)
  on conflict (company_id) do update
    set stripe_account_id = excluded.stripe_account_id,
        stripe_charges_enabled = excluded.stripe_charges_enabled,
        updated_at = now();
end;
$$;

-- ---------- restul la destinație ----------

create or replace function public.record_cash_payment(p_booking_id uuid, p_amount_cents int, p_idempotency_key text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_booking public.bookings%rowtype;
begin
  select * into v_booking from public.bookings where id = p_booking_id;
  if v_booking.id is null
     or not (public.is_company_staff(v_booking.company_id) or public.is_trip_driver(v_booking.trip_id)) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  -- Aceeași încasare retrimisă (ex. aplicația șoferului după lipsă de semnal): fără efect.
  if exists (select 1 from public.payments where method = 'CASH' and provider_ref = 'cash:' || p_idempotency_key) then
    return;
  end if;
  if coalesce(p_amount_cents, 0) <= 0 or coalesce(length(p_idempotency_key), 0) < 8
     or (v_booking.price_cents is not null and v_booking.amount_paid_cents + p_amount_cents > v_booking.price_cents) then
    raise exception 'PAYMENT_MISMATCH' using errcode = '22023';
  end if;
  insert into public.payments (company_id, booking_id, kind, method, amount_cents, currency, status, provider_ref, paid_at, created_by)
  values (v_booking.company_id, p_booking_id,
          case when v_booking.amount_paid_cents > 0 then 'REMAINDER' else 'FULL' end,
          'CASH', p_amount_cents, v_booking.currency, 'PAID', 'cash:' || p_idempotency_key, now(), auth.uid())
  on conflict (method, provider_ref) do nothing;
  perform public._refresh_booking_payment(p_booking_id);
end;
$$;

-- ---------- funcții pentru client ----------

create or replace function public.my_bookings()
returns table (
  booking_id      uuid,
  company_name    text,
  company_slug    text,
  trip_title      text,
  departure_at    timestamptz,
  from_name       text,
  to_name         text,
  passengers      int,
  status          public.booking_status,
  price_cents     int,
  amount_paid_cents int,
  payment_status  text,
  currency        text,
  cancel_until    timestamptz
)
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select b.id, co.name, co.slug, t.title, t.departure_at, fp.name, tp.name, b.passengers, b.status,
         b.price_cents, b.amount_paid_cents, b.payment_status, b.currency,
         t.departure_at - make_interval(hours => coalesce(ps.cancel_until_hours, 24))
  from public.bookings b
  join public.customers c on c.id = b.customer_id and c.user_id = auth.uid()
  join public.trips t on t.id = b.trip_id
  join public.companies co on co.id = b.company_id
  join public.trip_route_points fp on fp.trip_id = t.id and fp.seq = b.from_seq
  join public.trip_route_points tp on tp.trip_id = t.id and tp.seq = b.to_seq
  left join public.company_payment_settings ps on ps.company_id = b.company_id
  where auth.uid() is not null
  order by t.departure_at desc
  limit 100;
$$;

create or replace function public.client_cancel_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_booking public.bookings%rowtype;
  v_limit   timestamptz;
begin
  if not public.is_booking_client(p_booking_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select b.* into v_booking from public.bookings b where b.id = p_booking_id;
  select t.departure_at - make_interval(hours => coalesce(ps.cancel_until_hours, 24)) into v_limit
  from public.trips t left join public.company_payment_settings ps on ps.company_id = t.company_id
  where t.id = v_booking.trip_id;
  if v_booking.status in ('CANCELLED', 'COMPLETED', 'NO_SHOW') then
    return;
  end if;
  if now() > v_limit or v_booking.status not in ('HELD', 'CONFIRMED', 'DRIVER_ASSIGNED') then
    raise exception 'CANCELLATION_TOO_LATE' using errcode = '22023';
  end if;
  perform 1 from public.trips where id = v_booking.trip_id for update;
  update public.bookings set status = 'CANCELLED', cancel_reason = 'CLIENT_CANCELLED', hold_expires_at = null
  where id = p_booking_id;
  update public.booking_seats set released_at = now() where booking_id = p_booking_id and released_at is null;
  update public.payments set status = 'EXPIRED' where booking_id = p_booking_id and status = 'PENDING';
end;
$$;

create or replace function public.client_tracking_link(p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_booking_client(p_booking_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  return public.worker_tracking_link(p_booking_id);
end;
$$;

-- ---------- lista de pasageri: cât mai e de încasat ----------

drop function public.get_passenger_manifest(uuid);
create function public.get_passenger_manifest(p_trip_id uuid)
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
  status          public.booking_status,
  amount_paid_cents int,
  amount_due_cents  int
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
         b.payment_method, b.price_cents, b.currency, b.status,
         b.amount_paid_cents, greatest(coalesce(b.price_cents, 0) - b.amount_paid_cents, 0)
  from public.bookings b
  join public.customers c on c.id = b.customer_id
  join public.trip_route_points fp on fp.trip_id = b.trip_id and fp.seq = b.from_seq
  join public.trip_route_points tp on tp.trip_id = b.trip_id and tp.seq = b.to_seq
  left join public.trip_stops ps on ps.booking_id = b.id and ps.kind = 'PICKUP'
  where b.trip_id = p_trip_id and b.status not in ('CANCELLED', 'NO_SHOW', 'HELD', 'REQUESTED')
  order by ps.seq nulls last, c.full_name;
end;
$$;

-- ---------- drepturi ----------

revoke execute on function public._trip_price_cents(uuid, int, int), public._refresh_booking_payment(uuid),
  public._create_booking_core(uuid, uuid, uuid, int, int, int, text, double precision, double precision, text,
                              text, double precision, double precision, int, text, public.payment_method,
                              boolean, int, text, text)
  from public, anon, authenticated;
revoke execute on function public.search_marketplace(double precision, double precision, double precision,
  double precision, int, timestamptz, timestamptz, double precision) from public;
revoke execute on function public.get_marketplace_offer(uuid, int, int, int) from public;
grant execute on function public.get_marketplace_offer(uuid, int, int, int) to anon, authenticated;
grant execute on function public.search_marketplace(double precision, double precision, double precision,
  double precision, int, timestamptz, timestamptz, double precision) to anon, authenticated;
revoke execute on function public.book_marketplace(uuid, int, int, int, text, text, text, text),
  public.attach_payment_session(uuid, text), public.record_cash_payment(uuid, int, text),
  public.my_bookings(), public.client_cancel_booking(uuid), public.client_tracking_link(uuid),
  public.is_booking_client(uuid), public.get_passenger_manifest(uuid),
  public.book_seats(uuid, uuid, int, int, int, text, double precision, double precision, text,
                    text, double precision, double precision, int, text, public.payment_method, boolean, int, text),
  public.create_trip_from_template(uuid, uuid, uuid, timestamptz, text)
  from public, anon;
grant execute on function public.book_marketplace(uuid, int, int, int, text, text, text, text),
  public.attach_payment_session(uuid, text), public.record_cash_payment(uuid, int, text),
  public.my_bookings(), public.client_cancel_booking(uuid), public.client_tracking_link(uuid),
  public.is_booking_client(uuid), public.get_passenger_manifest(uuid),
  public.book_seats(uuid, uuid, int, int, int, text, double precision, double precision, text,
                    text, double precision, double precision, int, text, public.payment_method, boolean, int, text),
  public.create_trip_from_template(uuid, uuid, uuid, timestamptz, text)
  to authenticated;
revoke execute on function public.mark_payment_paid(text, int), public.mark_payment_expired(text),
  public.mark_payment_refunded(text), public.set_company_stripe_account(uuid, text, boolean)
  from public, anon, authenticated;
grant execute on function public.mark_payment_paid(text, int), public.mark_payment_expired(text),
  public.mark_payment_refunded(text), public.set_company_stripe_account(uuid, text, boolean)
  to service_role;
