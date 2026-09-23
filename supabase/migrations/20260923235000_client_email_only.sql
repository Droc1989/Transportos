-- 2500 — Conturi de client doar cu email, fără confirmarea telefonului (decizia proprietarului)
--
-- Clientul își face contul cu email și rezervă online. Contul NU se leagă de fișa de client a
-- firmei (care e după telefon), deci:
--   * clientul vede doar rezervările făcute de contul lui (bookings.client_user_id);
--   * rezervările vechi, făcute prin telefon la dispecer, nu apar în contul lui;
--   * firma vede rezervarea online la fișa clientului cu acel telefon (istoricul rămâne la firmă);
--   * două conturi care folosesc același telefon nu își văd rezervările unul altuia.
-- Înlocuiește regula din 2400 care cerea telefon confirmat (PHONE_NOT_VERIFIED): acum un client cu
-- rezervări vechi prin telefon nu mai e blocat la rezervarea online.

alter table public.bookings
  add column client_user_id uuid references auth.users (id) on delete set null,
  add column client_name text check (client_name is null or length(client_name) <= 120);
create index bookings_client_user_idx on public.bookings (client_user_id) where client_user_id is not null;

-- Rezervările online existente (din 2400) trec la contul care le-a făcut.
update public.bookings b set client_user_id = c.user_id, client_name = coalesce(b.client_name, c.full_name)
from public.customers c
where c.id = b.customer_id and b.source = 'MARKETPLACE' and c.user_id is not null and b.client_user_id is null;

-- Clientul „deține” doar rezervările făcute de contul lui.
create or replace function public.is_booking_client(p_booking uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.bookings b
    where b.id = p_booking and auth.uid() is not null and b.client_user_id = auth.uid()
  );
$$;

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
  select b.id into v_booking from public.bookings b
  where b.company_id = v_trip.company_id and b.idempotency_key = p_idempotency_key and b.client_user_id = auth.uid();
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

  -- Fișa de client a firmei (după telefon): se folosește fișa existentă sau se creează una.
  -- Contul NU se leagă de fișă (fără confirmarea telefonului), deci clientul nu vede istoricul
  -- fișei; vede doar rezervările făcute de contul lui (bookings.client_user_id).
  select * into v_customer from public.customers where company_id = v_trip.company_id and phone = v_profile.phone;
  if v_customer.id is null then
    insert into public.customers (company_id, full_name, phone, locale)
    values (v_trip.company_id, v_profile.full_name, v_profile.phone, v_profile.locale)
    returning * into v_customer;
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

  update public.bookings set client_user_id = auth.uid(), client_name = v_profile.full_name where id = v_booking;

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
  join public.trips t on t.id = b.trip_id
  join public.companies co on co.id = b.company_id
  join public.trip_route_points fp on fp.trip_id = t.id and fp.seq = b.from_seq
  join public.trip_route_points tp on tp.trip_id = t.id and tp.seq = b.to_seq
  left join public.company_payment_settings ps on ps.company_id = b.company_id
  where auth.uid() is not null and b.client_user_id = auth.uid()
  order by t.departure_at desc
  limit 100;
$$;

-- Lista de pasageri: numele declarat de client la rezervarea online, altfel cel din fișă.
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
  select b.id, ps.seq, coalesce(b.client_name, c.full_name), c.phone, b.passengers,
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

-- Câmpurile gestionate de platformă nu se scriu direct de personal: cui aparține rezervarea
-- online și cât s-a plătit (sumele vin doar din tabelul de plăți, prin funcții).
create or replace function public.bookings_guard()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if current_user in ('authenticated', 'anon')
     and (new.client_user_id is distinct from old.client_user_id
          or new.client_name is distinct from old.client_name
          or new.source is distinct from old.source
          or new.amount_paid_cents is distinct from old.amount_paid_cents
          or new.payment_status is distinct from old.payment_status) then
    raise exception 'FIELD_NOT_EDITABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger bookings_guard before update on public.bookings
for each row execute function public.bookings_guard();
revoke execute on function public.bookings_guard() from public, anon, authenticated;
