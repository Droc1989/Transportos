-- 1600 — Notificări (coadă de trimis) și detecție automată din GPS
--
-- Notificări: baza de date doar pune mesajele într-o coadă (notification_outbox), o singură
-- dată pe motiv (dedupe_key). Un worker cu service_role le ia cu claim_notifications,
-- le trimite prin NotificationProvider și raportează cu finish_notification. Eșecurile se
-- reîncearcă de până la 5 ori, cu pauze tot mai mari.
--
-- Motive:
--   BOOKING_CONFIRMED  — rezervarea e confirmată
--   TRIP_CANCELLED     — firma a anulat cursa
--   PICKUP_ETA         — „ajunge în N minute” (pragurile din company_settings.eta_notify_minutes)
--   DRIVER_ARRIVED     — șoferul a ajuns la punctul de preluare
--
-- Detecție din GPS (la fiecare poziție nouă, în ingest_position), pentru următoarea oprire:
--   * sub 2 km: oprirea devine APPROACHING, rezervarea APPROACHING, eveniment PICKUP_APPROACHING;
--   * preluare ratată: vehiculul a trecut la sub 300 m de punct, iar acum distanța a crescut cu
--     peste 800 m fără ca clientul să urce → PICKUP_AT_RISK; cu peste 3 km → PICKUP_MISSED.
--     Marja (histerezis) evită alarmele false din poziții GPS imprecise.

alter table public.trip_stops add column min_distance_m real;

create table public.notification_outbox (
  id               bigint generated always as identity primary key,
  company_id       uuid not null references public.companies (id) on delete cascade,
  booking_id       uuid,
  template_key     text not null check (template_key ~ '^[A-Z_]+$'),
  channel          text not null check (channel in ('PUSH', 'SMS', 'WHATSAPP', 'EMAIL')),
  recipient        text not null,
  locale           text not null default 'ro',
  params           jsonb not null default '{}'::jsonb,
  status           text not null default 'PENDING'
                   check (status in ('PENDING', 'SENDING', 'SENT', 'FAILED', 'CANCELLED')),
  attempts         int not null default 0,
  next_attempt_at  timestamptz not null default now(),
  dedupe_key       text not null,
  created_at       timestamptz not null default now(),
  sent_at          timestamptz,
  last_error       text,
  unique (company_id, dedupe_key),
  foreign key (booking_id, company_id) references public.bookings (id, company_id) on delete cascade
);
create index notification_outbox_due_idx on public.notification_outbox (next_attempt_at)
  where status in ('PENDING', 'SENDING');
create index notification_outbox_booking_idx on public.notification_outbox (booking_id);

alter table public.notification_outbox enable row level security;
create policy notification_outbox_select on public.notification_outbox for select to authenticated
  using (public.is_company_staff(company_id));
grant select on public.notification_outbox to authenticated;
revoke insert, update, delete on public.notification_outbox from authenticated;

-- Pune un mesaj pentru clientul unei rezervări în coadă (o singură dată pe dedupe_key).
create or replace function public._enqueue_customer_notification(
  p_booking_id uuid, p_template text, p_dedupe text, p_params jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company  uuid;
  v_phone    text;
  v_locale   text;
  v_title    text;
  v_company_name text;
begin
  select b.company_id, c.phone, c.locale, t.title, co.name
    into v_company, v_phone, v_locale, v_title, v_company_name
  from public.bookings b
  join public.customers c  on c.id = b.customer_id
  join public.trips t      on t.id = b.trip_id
  join public.companies co on co.id = b.company_id
  where b.id = p_booking_id;
  if v_company is null then
    return;
  end if;

  insert into public.notification_outbox
    (company_id, booking_id, template_key, channel, recipient, locale, params, dedupe_key)
  values (
    v_company, p_booking_id, p_template,
    case when public.has_feature(v_company, 'sms_whatsapp') then 'WHATSAPP' else 'PUSH' end,
    v_phone, v_locale,
    jsonb_build_object('trip_title', v_title, 'company', v_company_name) || coalesce(p_params, '{}'::jsonb),
    p_dedupe
  )
  on conflict (company_id, dedupe_key) do nothing;
end;
$$;

-- ---------- declanșatoare pe rezervări ----------

create or replace function public.bookings_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'CONFIRMED' and (tg_op = 'INSERT' or old.status is distinct from 'CONFIRMED')
     and (tg_op = 'INSERT' or old.status in ('HELD', 'REQUESTED')) then
    perform public._enqueue_customer_notification(new.id, 'BOOKING_CONFIRMED', 'confirmed:' || new.id);
  end if;

  if tg_op = 'UPDATE' and new.status in ('CANCELLED', 'NO_SHOW', 'COMPLETED')
     and old.status is distinct from new.status then
    -- mesajele încă netrimise nu mai au sens
    update public.notification_outbox set status = 'CANCELLED'
    where booking_id = new.id and status = 'PENDING';
    if new.status = 'CANCELLED' and new.cancel_reason = 'TRIP_CANCELLED' then
      perform public._enqueue_customer_notification(new.id, 'TRIP_CANCELLED', 'trip_cancelled:' || new.id);
    end if;
  end if;
  return null;
end;
$$;

create trigger bookings_notify after insert or update of status on public.bookings
for each row execute function public.bookings_notify();

-- ---------- „ajunge în N minute” (rulat o dată pe minut) ----------

create or replace function public.enqueue_eta_notifications()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row   record;
  v_count int := 0;
begin
  for v_row in
    select b.id as booking_id, s.planned_at, s.eta_at,
           coalesce(cs.eta_notify_minutes, '{30,10}') as thresholds,
           extract(epoch from (coalesce(s.eta_at, s.planned_at) - now())) / 60.0 as minutes_left
    from public.trips t
    join public.trip_stops s on s.trip_id = t.id and s.kind = 'PICKUP' and s.status in ('PLANNED', 'APPROACHING')
    join public.bookings b   on b.id = s.booking_id
                            and b.status in ('CONFIRMED', 'DRIVER_ASSIGNED', 'APPROACHING')
    left join public.company_settings cs on cs.company_id = t.company_id
    where t.status = 'IN_PROGRESS'
      and coalesce(s.eta_at, s.planned_at) is not null
      and public.has_feature(t.company_id, 'tracking_link')
  loop
    declare
      v_threshold int;
    begin
      -- cel mai mic prag deja atins (ex. 8 min rămase → pragul 10, nu 30)
      select min(x) into v_threshold
      from unnest(v_row.thresholds) as x
      where v_row.minutes_left <= x and v_row.minutes_left > -5;

      if v_threshold is not null and not exists (
        select 1 from public.notification_outbox o
        where o.booking_id = v_row.booking_id and o.template_key = 'PICKUP_ETA'
          and (o.params ->> 'minutes')::int <= v_threshold
      ) then
        perform public._enqueue_customer_notification(
          v_row.booking_id, 'PICKUP_ETA', 'eta:' || v_row.booking_id || ':' || v_threshold,
          jsonb_build_object('minutes', v_threshold,
                             'eta_at', coalesce(v_row.eta_at, v_row.planned_at)));
        v_count := v_count + 1;
      end if;
    end;
  end loop;
  return v_count;
end;
$$;

-- ETA-uri actualizate de worker (ex. Google Routes cu trafic, în ultimele ~45 de minute).
create or replace function public.update_stop_etas(p_trip_id uuid, p_stop_ids uuid[], p_etas timestamptz[])
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
begin
  if coalesce(array_length(p_stop_ids, 1), 0) <> coalesce(array_length(p_etas, 1), 0) then
    raise exception 'INVALID_SEGMENT' using errcode = '22023';
  end if;
  update public.trip_stops s set eta_at = u.eta
  from unnest(p_stop_ids, p_etas) as u(id, eta)
  where s.id = u.id and s.trip_id = p_trip_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------- worker: preia și raportează ----------

create or replace function public.claim_notifications(p_limit int default 50)
returns setof public.notification_outbox
language sql
security definer
set search_path = public, pg_temp
as $$
  with due as (
    select id from public.notification_outbox
    where (status = 'PENDING' and next_attempt_at <= now())
       or (status = 'SENDING' and next_attempt_at <= now())  -- worker oprit la jumătate
    order by id
    limit greatest(p_limit, 1)
    for update skip locked
  )
  update public.notification_outbox o
  set status = 'SENDING', attempts = o.attempts + 1, next_attempt_at = now() + interval '10 minutes'
  from due where o.id = due.id
  returning o.*;
$$;

create or replace function public.finish_notification(p_id bigint, p_ok boolean, p_error text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.notification_outbox
  set status = case when p_ok then 'SENT'
                    when attempts >= 5 then 'FAILED'
                    else 'PENDING' end,
      sent_at = case when p_ok then now() end,
      last_error = case when p_ok then null else left(p_error, 500) end,
      next_attempt_at = case when p_ok then next_attempt_at
                             else now() + make_interval(mins => power(2, attempts)::int) end
  where id = p_id and status = 'SENDING';
end;
$$;

-- ---------- „șoferul a ajuns” trimite și mesaj clientului ----------

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

    perform public._enqueue_customer_notification(v_stop.booking_id, 'DRIVER_ARRIVED', 'arrived:' || v_stop.booking_id);
  end if;
end;
$$;

-- ---------- detecție din GPS ----------

create or replace function public._process_position(p_trip_id uuid, p_location extensions.geography)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  c_approach_m constant real := 2000;
  c_near_m     constant real := 300;
  c_risk_m     constant real := 800;
  c_missed_m   constant real := 3000;
  v_stop       public.trip_stops%rowtype;
  v_distance   real;
  v_min        real;
begin
  if not exists (select 1 from public.trips where id = p_trip_id and status = 'IN_PROGRESS') then
    return;
  end if;

  select * into v_stop from public.trip_stops
  where trip_id = p_trip_id and status in ('PLANNED', 'APPROACHING') and location is not null
  order by seq limit 1
  for update;
  if v_stop.id is null then
    return;
  end if;

  v_distance := st_distance(p_location, v_stop.location);
  v_min := least(coalesce(v_stop.min_distance_m, v_distance), v_distance);
  update public.trip_stops set min_distance_m = v_min where id = v_stop.id;

  if v_stop.status = 'PLANNED' and v_distance <= c_approach_m then
    update public.trip_stops set status = 'APPROACHING' where id = v_stop.id;
    if v_stop.kind = 'PICKUP' then
      update public.bookings set status = 'APPROACHING'
      where id = v_stop.booking_id and status in ('CONFIRMED', 'DRIVER_ASSIGNED');
      perform public._trip_event(v_stop.company_id, p_trip_id, v_stop.booking_id,
                                 'PICKUP_APPROACHING', 'approach:' || v_stop.id);
    end if;
  end if;

  if v_stop.kind = 'PICKUP' and v_min <= c_near_m then
    if v_distance >= v_min + c_missed_m then
      perform public._trip_event(v_stop.company_id, p_trip_id, v_stop.booking_id,
                                 'PICKUP_MISSED', 'missed:' || v_stop.id,
                                 jsonb_build_object('distance_m', round(v_distance)));
    elsif v_distance >= v_min + c_risk_m then
      perform public._trip_event(v_stop.company_id, p_trip_id, v_stop.booking_id,
                                 'PICKUP_AT_RISK', 'risk:' || v_stop.id,
                                 jsonb_build_object('distance_m', round(v_distance)));
    end if;
  end if;
end;
$$;

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
  v_latest    int;
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
  get diagnostics v_latest = row_count;

  -- Detecția rulează doar pe poziția cea mai nouă (nu pe cele sosite întârziat).
  if v_inserted > 0 and v_latest > 0 and p_trip_id is not null then
    perform public._process_position(p_trip_id, v_location);
  end if;

  return v_inserted > 0;
end;
$$;

-- ---------- alerte pentru dispecer ----------

create or replace function public.get_dispatch_alerts(p_company_id uuid, p_since interval default interval '6 hours')
returns table (
  kind         text,
  ref_id       uuid,
  trip_id      uuid,
  booking_id   uuid,
  severity     text,
  occurred_at  timestamptz,
  details      jsonb
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
  return query
  select 'EMERGENCY', e.id, e.trip_id, null::uuid, e.severity, e.created_at,
         jsonb_build_object('status', e.status, 'vehicle_id', e.vehicle_id, 'source', e.source)
  from public.emergency_events e
  where e.company_id = p_company_id and e.status = 'OPEN'
  union all
  select ev.type::text, ev.id, ev.trip_id, ev.booking_id,
         case ev.type when 'PICKUP_MISSED' then 'HIGH' else 'MEDIUM' end,
         ev.occurred_at, ev.payload
  from public.trip_events ev
  join public.bookings b on b.id = ev.booking_id
  where ev.company_id = p_company_id
    and ev.type in ('PICKUP_AT_RISK', 'PICKUP_MISSED')
    and ev.occurred_at > now() - p_since
    and b.status not in ('ON_BOARD', 'COMPLETED', 'CANCELLED', 'NO_SHOW')
  order by 6 desc;
end;
$$;

revoke execute on function public._enqueue_customer_notification(uuid, text, text, jsonb),
  public.bookings_notify(), public._process_position(uuid, extensions.geography)
  from public, anon, authenticated;
revoke execute on function public.enqueue_eta_notifications(), public.claim_notifications(int),
  public.finish_notification(bigint, boolean, text), public.update_stop_etas(uuid, uuid[], timestamptz[])
  from public, anon, authenticated;
grant execute on function public.enqueue_eta_notifications(), public.claim_notifications(int),
  public.finish_notification(bigint, boolean, text), public.update_stop_etas(uuid, uuid[], timestamptz[])
  to service_role;
revoke execute on function public.get_dispatch_alerts(uuid, interval), public.mark_stop_arrived(uuid),
  public.ingest_position(uuid, double precision, double precision, timestamptz, real, real, uuid) from public, anon;
grant execute on function public.get_dispatch_alerts(uuid, interval), public.mark_stop_arrived(uuid),
  public.ingest_position(uuid, double precision, double precision, timestamptz, real, real, uuid) to authenticated;

-- În Supabase, cu pg_cron:
-- select cron.schedule('eta-notifications', '* * * * *', $$select public.enqueue_eta_notifications()$$);
