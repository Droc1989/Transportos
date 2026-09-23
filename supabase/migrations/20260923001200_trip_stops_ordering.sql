-- 1200 — Opririle cursei: create automat din rezervări, ordonate pe traseu
--
-- * La fiecare rezervare nouă se creează o oprire de urcare (PICKUP) și una de coborâre
--   (DROPOFF). Locul lor în listă se alege după poziția pe traseu (proiecția pe route_line),
--   fără să strice ordinea pe care dispecerul a aranjat-o deja manual.
-- * Regula de bază: urcarea unui client e mereu înaintea coborârii lui.
-- * Rezervarea anulată: opririle ei devin SKIPPED și nu mai apar în listă.
-- * Orele planificate (planned_at) le calculează aplicația, prin RoutingProvider (OSRM),
--   și le salvează cu set_stop_planned_times.

-- Poziția unui punct pe traseul cursei: 0 = început, 1 = sfârșit.
create or replace function public._stop_key(p_trip_id uuid, p_location extensions.geography)
returns double precision
language sql stable
set search_path = public, extensions, pg_temp
as $$
  select coalesce(
    (select st_linelocatepoint(t.route_line::geometry, p_location::geometry)
     from public.trips t where t.id = p_trip_id and t.route_line is not null),
    0
  );
$$;

-- Verifică ordinea: urcarea fiecărui client înaintea coborârii.
create or replace function public._validate_stop_order(p_trip_id uuid)
returns void
language plpgsql stable
set search_path = public, pg_temp
as $$
begin
  if exists (
    select 1
    from public.trip_stops p
    join public.trip_stops d on d.booking_id = p.booking_id and d.kind = 'DROPOFF'
    where p.trip_id = p_trip_id and p.kind = 'PICKUP'
      and p.status <> 'SKIPPED' and d.status <> 'SKIPPED'
      and p.seq > d.seq
  ) then
    raise exception 'STOP_ORDER_INVALID' using errcode = '22023';
  end if;
end;
$$;

-- Inserează o oprire după ultima oprire activă aflată înaintea ei pe traseu,
-- dar nu mai devreme de p_min_seq. Întoarce seq-ul primit.
create or replace function public._insert_stop(
  p_company_id uuid, p_trip_id uuid, p_booking_id uuid, p_kind public.stop_kind,
  p_address text, p_location extensions.geography, p_min_seq int
)
returns int
language plpgsql
set search_path = public, extensions, pg_temp
as $$
declare
  v_key   double precision := public._stop_key(p_trip_id, p_location);
  v_after int;
  v_seq   int;
begin
  select max(seq) into v_after
  from public.trip_stops
  where trip_id = p_trip_id and status <> 'SKIPPED'
    and public._stop_key(p_trip_id, location) <= v_key;

  v_seq := greatest(coalesce(v_after, -1) + 1, p_min_seq);

  update public.trip_stops set seq = seq + 1
  where trip_id = p_trip_id and seq >= v_seq;

  insert into public.trip_stops (company_id, trip_id, booking_id, kind, seq, address, location)
  values (p_company_id, p_trip_id, p_booking_id, p_kind, v_seq, p_address, p_location);

  return v_seq;
end;
$$;

create or replace function public.bookings_create_stops()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_pickup_loc  extensions.geography;
  v_drop_loc    extensions.geography;
  v_pickup_seq  int;
begin
  if new.status in ('CANCELLED', 'NO_SHOW', 'MISSED_PICKUP', 'COMPLETED') then
    return null;
  end if;

  -- Fără coordonate exacte, folosim punctul de traseu (orașul) ales la rezervare.
  select coalesce(new.pickup_location, rp.location) into v_pickup_loc
  from public.trip_route_points rp where rp.trip_id = new.trip_id and rp.seq = new.from_seq;
  select coalesce(new.dropoff_location, rp.location) into v_drop_loc
  from public.trip_route_points rp where rp.trip_id = new.trip_id and rp.seq = new.to_seq;

  v_pickup_seq := public._insert_stop(new.company_id, new.trip_id, new.id, 'PICKUP',
                                      new.pickup_address, v_pickup_loc, 0);
  perform public._insert_stop(new.company_id, new.trip_id, new.id, 'DROPOFF',
                              new.dropoff_address, v_drop_loc, v_pickup_seq + 1);
  return null;
end;
$$;

create trigger bookings_create_stops after insert on public.bookings
for each row execute function public.bookings_create_stops();

create or replace function public.bookings_skip_stops()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.trip_stops set status = 'SKIPPED'
  where booking_id = new.id and status in ('PLANNED', 'APPROACHING');
  return null;
end;
$$;

create trigger bookings_skip_stops after update of status on public.bookings
for each row when (new.status in ('CANCELLED', 'NO_SHOW') and old.status is distinct from new.status)
execute function public.bookings_skip_stops();

-- ---------- funcții pentru dispecer ----------

-- Mută o oprire cu o poziție mai sus (-1) sau mai jos (+1).
create or replace function public.move_trip_stop(p_stop_id uuid, p_delta int)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_stop      public.trip_stops%rowtype;
  v_neighbor  public.trip_stops%rowtype;
begin
  select * into v_stop from public.trip_stops where id = p_stop_id;
  if v_stop.id is null then
    raise exception 'BOOKING_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.is_company_staff(v_stop.company_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  perform 1 from public.trips where id = v_stop.trip_id for update;

  select * into v_neighbor from public.trip_stops
  where trip_id = v_stop.trip_id and status <> 'SKIPPED'
    and case when p_delta < 0 then seq < v_stop.seq else seq > v_stop.seq end
  order by case when p_delta < 0 then -seq else seq end
  limit 1;

  if v_neighbor.id is null then
    return; -- deja prima sau ultima
  end if;
  if v_stop.status in ('ARRIVED', 'DONE') or v_neighbor.status in ('ARRIVED', 'DONE') then
    raise exception 'STOP_ORDER_INVALID' using errcode = '22023';
  end if;

  update public.trip_stops set seq = case id when v_stop.id then v_neighbor.seq else v_stop.seq end
  where id in (v_stop.id, v_neighbor.id);

  perform public._validate_stop_order(v_stop.trip_id);
end;
$$;

-- Ordonează automat opririle rămase după poziția pe traseu.
-- Opririle deja făcute rămân primele, în ordinea lor.
create or replace function public.auto_order_trip_stops(p_trip_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.trips where id = p_trip_id for update;
  if v_company is null then
    raise exception 'TRIP_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  with keyed as (
    select s.id, s.kind, s.booking_id, s.status, s.seq,
           public._stop_key(p_trip_id, s.location) as k
    from public.trip_stops s
    where s.trip_id = p_trip_id
  ),
  adjusted as (
    -- coborârea nu poate fi înaintea urcării aceluiași client
    select k1.*,
           case when k1.kind = 'DROPOFF'
                then greatest(k1.k, coalesce((select k2.k from keyed k2
                                              where k2.booking_id = k1.booking_id and k2.kind = 'PICKUP'), 0) + 1e-9)
                else k1.k end as sort_key
    from keyed k1
  ),
  ordered as (
    select id,
           row_number() over (
             order by
               case when status in ('ARRIVED', 'DONE') then 0
                    when status = 'SKIPPED' then 2 else 1 end,
               case when status in ('ARRIVED', 'DONE') then seq end,
               sort_key,
               case kind when 'DROPOFF' then 0 else 1 end,
               seq
           ) - 1 as new_seq
    from adjusted
  )
  update public.trip_stops s set seq = o.new_seq
  from ordered o where o.id = s.id and s.seq <> o.new_seq;

  perform public._validate_stop_order(p_trip_id);
end;
$$;

-- Salvează orele planificate calculate de aplicație (listele au aceeași lungime și ordine).
create or replace function public.set_stop_planned_times(
  p_trip_id   uuid,
  p_stop_ids  uuid[],
  p_times     timestamptz[]
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
  v_count   int;
begin
  select company_id into v_company from public.trips where id = p_trip_id;
  if v_company is null or not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if coalesce(array_length(p_stop_ids, 1), 0) <> coalesce(array_length(p_times, 1), 0) then
    raise exception 'INVALID_SEGMENT' using errcode = '22023';
  end if;

  update public.trip_stops s set planned_at = u.t
  from unnest(p_stop_ids, p_times) as u(id, t)
  where s.id = u.id and s.trip_id = p_trip_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public._stop_key(uuid, extensions.geography),
  public._validate_stop_order(uuid),
  public._insert_stop(uuid, uuid, uuid, public.stop_kind, text, extensions.geography, int),
  public.bookings_create_stops(), public.bookings_skip_stops()
  from public, anon, authenticated;
revoke execute on function public.move_trip_stop(uuid, int), public.auto_order_trip_stops(uuid),
  public.set_stop_planned_times(uuid, uuid[], timestamptz[]) from public, anon;
grant execute on function public.move_trip_stop(uuid, int), public.auto_order_trip_stops(uuid),
  public.set_stop_planned_times(uuid, uuid[], timestamptz[]) to authenticated;
