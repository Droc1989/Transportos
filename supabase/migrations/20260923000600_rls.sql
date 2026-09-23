-- 0600 — Funcții de autorizare și politici RLS
-- Reguli (docs/adr/0001-tenancy-rls.md):
--   * personalul firmei (OWNER, ADMIN, DISPATCHER) vede tot ce ține de firma lui;
--   * șoferul vede doar cursele lui și rezervările/clienții de pe ele;
--   * Super Admin vede firme, abonamente și funcții, NU clienți, rezervări sau poziții;
--   * scrierile care țin de locuri și poziții trec doar prin funcții (0700).

-- ---------- funcții ajutătoare ----------

create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.platform_admins where user_id = auth.uid());
$$;

create or replace function public.company_role(p_company uuid)
returns public.member_role
language sql stable security definer
set search_path = public, pg_temp
as $$
  select role from public.company_members
  where company_id = p_company and user_id = auth.uid();
$$;

create or replace function public.is_company_member(p_company uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select public.company_role(p_company) is not null;
$$;

create or replace function public.is_company_staff(p_company uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.company_role(p_company) in ('OWNER', 'ADMIN', 'DISPATCHER'), false);
$$;

create or replace function public.is_company_admin(p_company uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.company_role(p_company) in ('OWNER', 'ADMIN'), false);
$$;

create or replace function public.is_trip_driver(p_trip uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.trips t
    join public.drivers d on d.id = t.driver_id and d.company_id = t.company_id
    where t.id = p_trip and d.user_id = auth.uid() and d.active
  );
$$;

-- Funcție activă = excepție setată de Super Admin, altfel inclusă în planul firmei.
-- La abonament anulat nu mai e nicio funcție activă.
create or replace function public.has_feature(p_company uuid, p_key text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select o.enabled from public.company_feature_overrides o
      where o.company_id = p_company and o.feature_key = p_key),
    exists (
      select 1
      from public.company_subscriptions s
      join public.plan_features pf on pf.plan_id = s.plan_id
      where s.company_id = p_company
        and pf.feature_key = p_key
        and s.status <> 'CANCELLED'
    )
  );
$$;

-- Firma poate crea date noi (rezervări, curse). În mod „doar citire” nu poate,
-- dar cursele deja începute continuă (poziții, evenimente, SOS nu depind de asta).
create or replace function public.company_can_write(p_company uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.companies c
    join public.company_subscriptions s on s.company_id = c.id
    where c.id = p_company
      and c.status = 'ACTIVE'
      and s.status in ('TRIAL', 'ACTIVE', 'PAST_DUE')
  );
$$;

-- ---------- activare RLS ----------

alter table public.companies                 enable row level security;
alter table public.company_settings          enable row level security;
alter table public.company_members           enable row level security;
alter table public.platform_admins           enable row level security;
alter table public.plans                     enable row level security;
alter table public.features                  enable row level security;
alter table public.plan_features             enable row level security;
alter table public.company_subscriptions     enable row level security;
alter table public.company_feature_overrides enable row level security;
alter table public.vehicles                  enable row level security;
alter table public.drivers                   enable row level security;
alter table public.customers                 enable row level security;
alter table public.trips                     enable row level security;
alter table public.trip_route_points         enable row level security;
alter table public.bookings                  enable row level security;
alter table public.booking_seats             enable row level security;
alter table public.trip_stops                enable row level security;
alter table public.vehicle_positions_current enable row level security;
alter table public.vehicle_positions         enable row level security;
alter table public.trip_events               enable row level security;
alter table public.notifications_sent        enable row level security;

-- ---------- platformă ----------

create policy companies_select on public.companies for select to authenticated
  using (public.is_company_member(id) or public.is_platform_admin());
create policy companies_insert on public.companies for insert to authenticated
  with check (public.is_platform_admin());
create policy companies_update on public.companies for update to authenticated
  using (public.is_company_admin(id) or public.is_platform_admin())
  with check (public.is_company_admin(id) or public.is_platform_admin());

create policy company_settings_select on public.company_settings for select to authenticated
  using (public.is_company_member(company_id));
create policy company_settings_write on public.company_settings for all to authenticated
  using (public.is_company_admin(company_id))
  with check (public.is_company_admin(company_id));

create policy company_members_select on public.company_members for select to authenticated
  using (public.is_company_member(company_id) or public.is_platform_admin());
create policy company_members_write on public.company_members for all to authenticated
  using (public.is_company_admin(company_id) or public.is_platform_admin())
  with check (public.is_company_admin(company_id) or public.is_platform_admin());

create policy platform_admins_self on public.platform_admins for select to authenticated
  using (user_id = auth.uid());

create policy plans_read on public.plans for select to authenticated using (true);
create policy plans_write on public.plans for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy features_read on public.features for select to authenticated using (true);
create policy features_write on public.features for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy plan_features_read on public.plan_features for select to authenticated using (true);
create policy plan_features_write on public.plan_features for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy subscriptions_select on public.company_subscriptions for select to authenticated
  using (public.is_company_admin(company_id) or public.is_platform_admin());
create policy subscriptions_write on public.company_subscriptions for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy overrides_select on public.company_feature_overrides for select to authenticated
  using (public.is_company_admin(company_id) or public.is_platform_admin());
create policy overrides_write on public.company_feature_overrides for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

-- ---------- flotă și clienți ----------

create policy vehicles_select on public.vehicles for select to authenticated
  using (public.is_company_member(company_id));
create policy vehicles_write on public.vehicles for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_write(company_id));

create policy drivers_select on public.drivers for select to authenticated
  using (public.is_company_staff(company_id) or user_id = auth.uid());
create policy drivers_write on public.drivers for all to authenticated
  using (public.is_company_admin(company_id))
  with check (public.is_company_admin(company_id) and public.company_can_write(company_id));

create policy customers_select on public.customers for select to authenticated
  using (
    public.is_company_staff(company_id)
    or exists (
      select 1 from public.bookings b
      where b.customer_id = customers.id and public.is_trip_driver(b.trip_id)
    )
  );
create policy customers_write on public.customers for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_write(company_id));

-- ---------- curse și rezervări ----------

create policy trips_select on public.trips for select to authenticated
  using (public.is_company_staff(company_id) or public.is_trip_driver(id));
create policy trips_write on public.trips for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_write(company_id));

create policy route_points_select on public.trip_route_points for select to authenticated
  using (public.is_company_staff(company_id) or public.is_trip_driver(trip_id));
create policy route_points_write on public.trip_route_points for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_write(company_id));

-- Rezervările se creează și se anulează doar prin funcțiile din 0700.
-- Personalul poate edita câmpuri descriptive (note, adrese, preț).
create policy bookings_select on public.bookings for select to authenticated
  using (public.is_company_staff(company_id) or public.is_trip_driver(trip_id));
create policy bookings_update on public.bookings for update to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id));

create policy booking_seats_select on public.booking_seats for select to authenticated
  using (public.is_company_staff(company_id) or public.is_trip_driver(trip_id));

create policy trip_stops_select on public.trip_stops for select to authenticated
  using (public.is_company_staff(company_id) or public.is_trip_driver(trip_id));
create policy trip_stops_write on public.trip_stops for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id));

-- ---------- urmărire ----------
-- Pozițiile se scriu doar prin public.ingest_position (0700).

create policy positions_current_select on public.vehicle_positions_current for select to authenticated
  using (public.is_company_staff(company_id) or (trip_id is not null and public.is_trip_driver(trip_id)));

create policy positions_select on public.vehicle_positions for select to authenticated
  using (public.is_company_staff(company_id));

create policy trip_events_select on public.trip_events for select to authenticated
  using (public.is_company_staff(company_id) or public.is_trip_driver(trip_id));
create policy trip_events_insert on public.trip_events for insert to authenticated
  with check (
    created_by = auth.uid()
    and (public.is_company_staff(company_id) or public.is_trip_driver(trip_id))
  );

create policy notifications_select on public.notifications_sent for select to authenticated
  using (public.is_company_staff(company_id));
-- scriere: doar service_role (workerul de notificări), care ocolește RLS.

-- ---------- drepturi ----------

revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;
