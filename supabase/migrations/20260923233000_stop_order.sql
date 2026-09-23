-- Ordinea opririlor stabilită de optimizare (Route Planner sau metoda locală), în siguranță.
--
-- Optimizarea reordonează doar opririle din aceeași „zonă”: aceeași oprire a rutei și același tip
-- (coborârile de la un punct înaintea urcărilor de la același punct). Astfel, nicio rezervare pe
-- porțiuni nu e încălcată: nimeni nu e luat înaintea celor de la punctele anterioare, iar coborârea
-- vine după urcare. Funcția verifică singură aceste reguli; o ordine care le încalcă e refuzată.

create or replace function public.set_trip_stop_order(p_trip_id uuid, p_stop_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_trip     public.trips%rowtype;
  v_expected int;
  v_bad      int;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if v_trip.id is null then
    raise exception 'TRIP_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.is_company_staff(v_trip.company_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_trip.status in ('COMPLETED', 'CANCELLED') then
    raise exception 'TRIP_CLOSED' using errcode = '22023';
  end if;

  -- exact opririle active ale cursei, fiecare o singură dată
  select count(*) into v_expected from public.trip_stops where trip_id = p_trip_id and status <> 'SKIPPED';
  if coalesce(array_length(p_stop_ids, 1), 0) <> v_expected
     or (select count(distinct x) from unnest(p_stop_ids) x) <> v_expected
     or exists (select 1 from unnest(p_stop_ids) x
                where not exists (select 1 from public.trip_stops s where s.id = x and s.trip_id = p_trip_id and s.status <> 'SKIPPED')) then
    raise exception 'INVALID_REQUEST' using errcode = '22023', detail = 'stops';
  end if;

  with ord as (
    select x.id, x.ord - 1 as new_seq, s.seq as old_seq, s.status, s.kind,
           case when s.kind = 'PICKUP' then b.from_seq else b.to_seq end as zone,
           case when s.kind = 'DROPOFF' then 0 else 1 end as kind_rank
    from unnest(p_stop_ids) with ordinality as x(id, ord)
    join public.trip_stops s on s.id = x.id
    join public.bookings b on b.id = s.booking_id
  ), checked as (
    select *, lag(zone) over (order by new_seq) as prev_zone, lag(kind_rank) over (order by new_seq) as prev_rank
    from ord
  )
  select count(*) into v_bad from checked
  where (status in ('ARRIVED', 'DONE') and new_seq <> old_seq)                 -- opririle făcute nu se mută
     or (prev_zone is not null and (zone < prev_zone or (zone = prev_zone and kind_rank < prev_rank)));
  if v_bad > 0 then
    raise exception 'INVALID_REQUEST' using errcode = '22023', detail = 'order';
  end if;

  update public.trip_stops s set seq = x.ord - 1
  from unnest(p_stop_ids) with ordinality as x(id, ord)
  where s.id = x.id;
  -- opririle sărite rămân după cele active
  update public.trip_stops s set seq = v_expected + r.rn - 1
  from (select id, row_number() over (order by seq) as rn from public.trip_stops
        where trip_id = p_trip_id and status = 'SKIPPED') r
  where s.id = r.id;
end;
$$;

revoke execute on function public.set_trip_stop_order(uuid, uuid[]) from public, anon;
grant execute on function public.set_trip_stop_order(uuid, uuid[]) to authenticated;
