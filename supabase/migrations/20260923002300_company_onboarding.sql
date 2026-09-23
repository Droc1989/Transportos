-- 2300 — Înscrierea firmelor, aprobarea de către Super Admin, microbuze cu poze și condiții,
--        profilul completat de șofer și aprobat de firmă (ADR-0008)
--
-- Flux:
--   1. Firma își face cont și se înscrie (register_company): starea PENDING_VERIFICATION.
--   2. În verificare își adaugă microbuzele: an, locuri, număr, poze (exterior + interior),
--      condiții dintr-o listă fixă, bagaje, declarațiile RCA și asigurare de pasageri cu expirare.
--      Nu poate face curse, rezervări, site sau șoferi până la aprobare.
--   3. Trimite cererea (submit_company_for_review) doar cu lista de verificare completă.
--   4. Super Admin vede firma și flota; microbuzele mai vechi decât anul minim (setare de
--      platformă, implicit 2012) apar marcate; decide pentru fiecare microbuz și pentru firmă.
--   5. Doar microbuzele aprobate pot face curse și apar la clienți. Și microbuzele adăugate după
--      aprobarea firmei trec prin aprobare. Schimbarea anului sau a numărului cere reaprobare.
--   6. Șoferul își completează profilul (poză, limbi, câteva rânduri, acord pentru afișare);
--      firma îl aprobă. Pe site apare doar profilul aprobat, cu acordul șoferului.
--
-- Coduri de eroare noi: SLUG_TAKEN, ALREADY_REGISTERED, REGISTRATION_INCOMPLETE,
-- VEHICLE_NOT_APPROVED, VEHICLE_INSURANCE_EXPIRED, NOT_SUBMITTED.

-- ---------- setări de platformă ----------

create table public.platform_settings (
  key         text primary key check (key ~ '^[a-z_]+$'),
  value       jsonb not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
insert into public.platform_settings (key, value) values ('min_vehicle_year', '2012');

alter table public.platform_settings enable row level security;
create policy platform_settings_read on public.platform_settings for select to authenticated using (true);
create policy platform_settings_write on public.platform_settings for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
grant select, insert, update on public.platform_settings to authenticated;

create or replace function public.min_vehicle_year()
returns int
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select (value #>> '{}')::int from public.platform_settings where key = 'min_vehicle_year'), 2012);
$$;

-- ---------- firma: date de înscriere ----------

alter table public.companies drop constraint if exists companies_status_check;
alter table public.companies add constraint companies_status_check
  check (status in ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED', 'REJECTED'));

alter table public.companies
  add column registration_no    text check (length(registration_no) <= 40),
  add column license_no         text check (length(license_no) <= 60),
  add column contact_phone      text check (length(contact_phone) <= 40),
  add column contact_email      text check (length(contact_email) <= 120),
  add column terms_accepted_at  timestamptz,
  add column terms_accepted_by  uuid,
  add column submitted_at       timestamptz,
  add column reviewed_at        timestamptz,
  add column reviewed_by        uuid,
  add column rejection_reason   text check (length(rejection_reason) <= 1000);

-- Firma în verificare își poate gestiona flota; restul lucrului cere firmă activă.
create or replace function public.company_can_manage_fleet(p_company uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.companies c
    join public.company_subscriptions s on s.company_id = c.id
    where c.id = p_company
      and c.status in ('PENDING_VERIFICATION', 'REJECTED', 'ACTIVE')
      and s.status in ('TRIAL', 'ACTIVE', 'PAST_DUE')
  );
$$;

-- ---------- microbuze: an, condiții, bagaje, asigurări, aprobare ----------

alter table public.vehicles
  add column manufacture_year          int check (manufacture_year is null or manufacture_year between 1980 and 2100),
  add column features                  text[] not null default '{}'
    check (features <@ array['AC', 'WIFI', 'USB', 'TOILET', 'RECLINING_SEATS', 'TRAILER',
                             'PETS_ALLOWED', 'WHEELCHAIR', 'CHILD_SEAT']::text[]),
  add column luggage_pieces            int check (luggage_pieces is null or luggage_pieces between 0 and 10),
  add column luggage_kg                int check (luggage_kg is null or luggage_kg between 0 and 200),
  add column rca_valid_until           date,
  add column passenger_insurance_until date,
  add column insurance_declared_at     timestamptz,
  add column insurance_declared_by     uuid,
  add column approval_status           text not null default 'PENDING'
    check (approval_status in ('PENDING', 'APPROVED', 'REJECTED')),
  add column approval_note             text check (length(approval_note) <= 1000),
  add column reviewed_at               timestamptz,
  add column reviewed_by               uuid;

create table public.vehicle_photos (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null,
  vehicle_id  uuid not null,
  kind        text not null check (kind in ('EXTERIOR', 'INTERIOR', 'LUGGAGE', 'OTHER')),
  url         text not null check (url ~ '^https?://'),
  sort        int not null default 0,
  created_at  timestamptz not null default now(),
  foreign key (vehicle_id, company_id) references public.vehicles (id, company_id) on delete cascade
);
create index vehicle_photos_vehicle_idx on public.vehicle_photos (vehicle_id, kind, sort);

-- Super Admin vede flota firmelor pentru aprobare (nu clienți, nu rezervări, nu GPS).
drop policy vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles for select to authenticated
  using (public.is_company_member(company_id) or public.is_platform_admin());
drop policy vehicles_write on public.vehicles;
create policy vehicles_write on public.vehicles for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_manage_fleet(company_id));

alter table public.vehicle_photos enable row level security;
create policy vehicle_photos_select on public.vehicle_photos for select to authenticated
  using (public.is_company_member(company_id) or public.is_platform_admin());
create policy vehicle_photos_write on public.vehicle_photos for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id) and public.company_can_manage_fleet(company_id));
grant select, insert, update, delete on public.vehicle_photos to authenticated;

-- Firma nu își aprobă singură microbuzele; o schimbare de an sau număr cere reaprobare.
-- security invoker: current_user e rolul celui care scrie. Scrierile directe ale
-- utilizatorilor vin ca `authenticated`; funcțiile platformei (review_vehicle etc.) rulează
-- ca proprietarul schemei și își verifică singure drepturile.
create or replace function public.vehicles_guard()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_platform_admin() then
    return new;  -- funcții de platformă, sistem, migrații, Super Admin
  end if;
  if tg_op = 'INSERT' then
    new.approval_status := 'PENDING';
    new.approval_note := null;
    new.reviewed_at := null;
    new.reviewed_by := null;
    return new;
  end if;
  if new.approval_status is distinct from old.approval_status
     or new.approval_note is distinct from old.approval_note
     or new.reviewed_at is distinct from old.reviewed_at
     or new.reviewed_by is distinct from old.reviewed_by then
    raise exception 'FIELD_NOT_EDITABLE' using errcode = '42501';
  end if;
  if old.approval_status = 'APPROVED'
     and (new.manufacture_year is distinct from old.manufacture_year or new.plate is distinct from old.plate) then
    new.approval_status := 'PENDING';
    new.reviewed_at := null;
    new.reviewed_by := null;
  end if;
  return new;
end;
$$;

create trigger vehicles_guard before insert or update on public.vehicles
for each row execute function public.vehicles_guard();

-- Declarațiile de asigurare, salvate cu data și cine a declarat.
create or replace function public.declare_vehicle_insurance(
  p_vehicle_id uuid, p_rca_until date, p_passenger_until date, p_confirm boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.vehicles where id = p_vehicle_id;
  if v_company is null or not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not coalesce(p_confirm, false) or p_rca_until is null or p_passenger_until is null
     or p_rca_until < current_date or p_passenger_until < current_date then
    raise exception 'INVALID_REQUEST' using errcode = '22023', detail = 'insurance';
  end if;
  update public.vehicles
  set rca_valid_until = p_rca_until, passenger_insurance_until = p_passenger_until,
      insurance_declared_at = now(), insurance_declared_by = auth.uid()
  where id = p_vehicle_id;
end;
$$;

-- Pe curse: doar microbuze aprobate, cu asigurările declarate valabile la plecare.
create or replace function public.trips_vehicle_check()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v public.vehicles%rowtype;
begin
  -- Datele pregătite de sistem (migrații, teste) nu au utilizator; orice cursă creată sau
  -- mutată de un utilizator trece prin verificare.
  if auth.uid() is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.vehicle_id is not distinct from old.vehicle_id
     and new.departure_at is not distinct from old.departure_at then
    return new;
  end if;
  select * into v from public.vehicles where id = new.vehicle_id;
  if v.approval_status <> 'APPROVED' then
    raise exception 'VEHICLE_NOT_APPROVED' using errcode = '22023';
  end if;
  if (v.rca_valid_until is not null and v.rca_valid_until < (new.departure_at at time zone 'UTC')::date)
     or (v.passenger_insurance_until is not null
         and v.passenger_insurance_until < (new.departure_at at time zone 'UTC')::date) then
    raise exception 'VEHICLE_INSURANCE_EXPIRED' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger trips_vehicle_check before insert or update of vehicle_id, departure_at on public.trips
for each row execute function public.trips_vehicle_check();

-- ---------- protecția câmpurilor firmei (înlocuiește varianta din 2200) ----------
-- Regula rămâne: utilizatorii nu schimbă direct status/slug/country. Funcțiile platformei
-- (submit_company_for_review, review_company) le schimbă după propriile verificări.
create or replace function public.companies_guard()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_platform_admin()
     and (new.status is distinct from old.status
          or new.slug is distinct from old.slug
          or new.country is distinct from old.country
          or new.id is distinct from old.id
          or new.submitted_at is distinct from old.submitted_at
          or new.reviewed_at is distinct from old.reviewed_at
          or new.reviewed_by is distinct from old.reviewed_by
          or new.rejection_reason is distinct from old.rejection_reason
          or new.terms_accepted_at is distinct from old.terms_accepted_at) then
    raise exception 'FIELD_NOT_EDITABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ---------- înscrierea firmei ----------

create or replace function public.register_company(
  p_name             text,
  p_slug             text,
  p_country          char(2),
  p_registration_no  text,
  p_license_no       text,
  p_contact_phone    text,
  p_accept_terms     boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id    uuid;
  v_slug  text := lower(trim(coalesce(p_slug, '')));
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if exists (select 1 from public.company_members where user_id = auth.uid() and role = 'OWNER') then
    raise exception 'ALREADY_REGISTERED' using errcode = '22023';
  end if;
  if not coalesce(p_accept_terms, false) or length(trim(coalesce(p_name, ''))) < 2
     or v_slug !~ '^[a-z0-9-]{2,60}$' or upper(p_country) not in ('RO', 'AT', 'DE')
     or length(trim(coalesce(p_registration_no, ''))) < 2 or length(trim(coalesce(p_license_no, ''))) < 2
     or length(regexp_replace(coalesce(p_contact_phone, ''), '[^0-9+]', '', 'g')) < 6 then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;
  if exists (select 1 from public.companies where slug = v_slug) then
    raise exception 'SLUG_TAKEN' using errcode = '23505';
  end if;

  select email into v_email from auth.users where id = auth.uid();

  insert into public.companies (name, slug, country, status, registration_no, license_no, contact_phone,
                                contact_email, terms_accepted_at, terms_accepted_by)
  values (trim(p_name), v_slug, upper(p_country), 'PENDING_VERIFICATION', trim(p_registration_no),
          trim(p_license_no), trim(p_contact_phone), v_email, now(), auth.uid())
  returning id into v_id;

  insert into public.company_settings (company_id, default_locale)
  values (v_id, case when upper(p_country) in ('AT', 'DE') then 'de' else 'ro' end);
  insert into public.company_subscriptions (company_id, plan_id, status, current_period_end)
  values (v_id, 'PILOT', 'TRIAL', (current_date + interval '1 month')::date);
  insert into public.company_members (company_id, user_id, role) values (v_id, auth.uid(), 'OWNER');
  return v_id;
end;
$$;

-- Lista de verificare înainte de trimitere (și pentru interfață).
create or replace function public.get_registration_checklist(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company public.companies%rowtype;
  v_vehicles jsonb;
begin
  if not (public.is_company_member(p_company_id) or public.is_platform_admin()) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select * into v_company from public.companies where id = p_company_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', v.id, 'label', v.label, 'approval_status', v.approval_status,
           'has_year', v.manufacture_year is not null,
           'below_min_year', v.manufacture_year < public.min_vehicle_year(),
           'has_exterior_photo', exists (select 1 from public.vehicle_photos p where p.vehicle_id = v.id and p.kind = 'EXTERIOR'),
           'has_interior_photo', exists (select 1 from public.vehicle_photos p where p.vehicle_id = v.id and p.kind = 'INTERIOR'),
           'has_insurance', v.insurance_declared_at is not null
                            and v.rca_valid_until >= current_date and v.passenger_insurance_until >= current_date,
           'complete', v.manufacture_year is not null
                       and exists (select 1 from public.vehicle_photos p where p.vehicle_id = v.id and p.kind = 'EXTERIOR')
                       and exists (select 1 from public.vehicle_photos p where p.vehicle_id = v.id and p.kind = 'INTERIOR')
                       and v.insurance_declared_at is not null
                       and v.rca_valid_until >= current_date and v.passenger_insurance_until >= current_date
         ) order by v.label), '[]'::jsonb)
    into v_vehicles
  from public.vehicles v where v.company_id = p_company_id;

  return jsonb_build_object(
    'status', v_company.status,
    'submitted_at', v_company.submitted_at,
    'rejection_reason', v_company.rejection_reason,
    'company_data', v_company.registration_no is not null and v_company.license_no is not null
                    and v_company.contact_phone is not null,
    'terms', v_company.terms_accepted_at is not null,
    'min_vehicle_year', public.min_vehicle_year(),
    'vehicles', v_vehicles,
    'has_complete_vehicle', exists (select 1 from jsonb_array_elements(v_vehicles) x where (x ->> 'complete')::boolean),
    'ready', v_company.registration_no is not null and v_company.terms_accepted_at is not null
             and exists (select 1 from jsonb_array_elements(v_vehicles) x where (x ->> 'complete')::boolean)
  );
end;
$$;

create or replace function public.submit_company_for_review(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_check jsonb;
begin
  if not public.is_company_admin(p_company_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  v_check := public.get_registration_checklist(p_company_id);
  if (v_check ->> 'status') not in ('PENDING_VERIFICATION', 'REJECTED') then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;
  if not (v_check ->> 'ready')::boolean then
    raise exception 'REGISTRATION_INCOMPLETE' using errcode = '22023';
  end if;
  update public.companies
  set status = 'PENDING_VERIFICATION', submitted_at = now(), rejection_reason = null
  where id = p_company_id;
end;
$$;

-- ---------- Super Admin: aprobare ----------

create or replace function public._notify_company_owner(p_company_id uuid, p_template text, p_params jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email  text;
  v_locale text;
begin
  select u.email, coalesce(cs.default_locale, 'ro') into v_email, v_locale
  from public.company_members m
  join auth.users u on u.id = m.user_id
  left join public.company_settings cs on cs.company_id = m.company_id
  where m.company_id = p_company_id and m.role = 'OWNER'
  order by m.created_at limit 1;
  if v_email is null then
    return;
  end if;
  insert into public.notification_outbox (company_id, template_key, channel, recipient, locale, params, dedupe_key)
  select p_company_id, p_template, 'EMAIL', v_email, v_locale,
         jsonb_build_object('company', c.name) || coalesce(p_params, '{}'::jsonb),
         lower(p_template) || ':' || p_company_id || ':' || extract(epoch from now())::bigint
  from public.companies c where c.id = p_company_id
  on conflict (company_id, dedupe_key) do nothing;
end;
$$;

create or replace function public.review_vehicle(p_vehicle_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not p_approve and length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'INVALID_REQUEST' using errcode = '22023', detail = 'reason';
  end if;
  update public.vehicles
  set approval_status = case when p_approve then 'APPROVED' else 'REJECTED' end,
      approval_note = nullif(trim(coalesce(p_note, '')), ''),
      reviewed_at = now(), reviewed_by = auth.uid()
  where id = p_vehicle_id;
  if not found then
    raise exception 'NOT_MEMBER' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.review_company(p_company_id uuid, p_approve boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company public.companies%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select * into v_company from public.companies where id = p_company_id for update;
  if v_company.id is null then
    raise exception 'NOT_MEMBER' using errcode = 'P0002';
  end if;
  if v_company.submitted_at is null then
    raise exception 'NOT_SUBMITTED' using errcode = '22023';
  end if;
  if not p_approve and length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'INVALID_REQUEST' using errcode = '22023', detail = 'reason';
  end if;
  if p_approve and not exists (select 1 from public.vehicles where company_id = p_company_id and approval_status = 'APPROVED') then
    raise exception 'VEHICLE_NOT_APPROVED' using errcode = '22023';
  end if;

  update public.companies
  set status = case when p_approve then 'ACTIVE' else 'REJECTED' end,
      reviewed_at = now(), reviewed_by = auth.uid(),
      rejection_reason = case when p_approve then null else trim(p_reason) end
  where id = p_company_id;

  perform public._notify_company_owner(p_company_id,
    case when p_approve then 'COMPANY_APPROVED' else 'COMPANY_REJECTED' end,
    case when p_approve then '{}'::jsonb else jsonb_build_object('reason', trim(p_reason)) end);
end;
$$;

create or replace function public.admin_pending_companies()
returns table (
  id               uuid,
  name             text,
  country          char(2),
  registration_no  text,
  license_no       text,
  contact_phone    text,
  contact_email    text,
  submitted_at     timestamptz,
  vehicles         int,
  vehicles_pending int,
  below_min_year   int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  return query
  select c.id, c.name, c.country, c.registration_no, c.license_no, c.contact_phone, c.contact_email, c.submitted_at,
         (select count(*)::int from public.vehicles v where v.company_id = c.id),
         (select count(*)::int from public.vehicles v where v.company_id = c.id and v.approval_status = 'PENDING'),
         (select count(*)::int from public.vehicles v where v.company_id = c.id and v.manufacture_year < public.min_vehicle_year())
  from public.companies c
  where (c.status = 'PENDING_VERIFICATION' and c.submitted_at is not null)
     or exists (select 1 from public.vehicles v where v.company_id = c.id and v.approval_status = 'PENDING'
                and c.status = 'ACTIVE')
  order by c.submitted_at nulls last;
end;
$$;

-- ---------- profilul completat de șofer, aprobat de firmă ----------

alter table public.drivers
  add column profile_status text not null default 'DRAFT'
    check (profile_status in ('DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED')),
  add column profile_note text check (length(profile_note) <= 500);

-- Șoferul își scrie singur profilul și își dă singur acordul pentru afișare.
create or replace function public.update_my_driver_profile(
  p_company_id     uuid,
  p_bio            text,
  p_languages      text[],
  p_driving_since  int,
  p_photo_url      text,
  p_public_consent boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or public.company_role(p_company_id) is distinct from 'DRIVER' then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.drivers
  set public_bio = nullif(trim(coalesce(p_bio, '')), ''),
      languages = coalesce(p_languages, '{}'),
      driving_since = p_driving_since,
      photo_url = coalesce(p_photo_url, photo_url),
      public_consent_at = case when p_public_consent then coalesce(public_consent_at, now()) else null end,
      public_consent_by = case when p_public_consent then auth.uid() else null end,
      public_profile = case when p_public_consent then public_profile else false end,
      profile_status = 'SUBMITTED',
      profile_note = null
  where company_id = p_company_id and user_id = auth.uid();
  if not found then
    raise exception 'NOT_MEMBER' using errcode = 'P0002';
  end if;
end;
$$;

-- Firma aprobă profilul (și îl publică pe site doar dacă șoferul și-a dat acordul).
create or replace function public.review_driver_profile(p_driver_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_driver public.drivers%rowtype;
begin
  select * into v_driver from public.drivers where id = p_driver_id;
  if v_driver.id is null or not public.is_company_admin(v_driver.company_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.drivers
  set profile_status = case when p_approve then 'APPROVED' else 'REJECTED' end,
      profile_note = nullif(trim(coalesce(p_note, '')), ''),
      public_profile = p_approve and public_consent_at is not null
  where id = p_driver_id;
end;
$$;

-- Acordul confirmat de admin (acord scris pe hârtie) aprobă și profilul.
create or replace function public.set_driver_public_profile(
  p_driver_id      uuid,
  p_public         boolean,
  p_consent        boolean,
  p_bio            text default null,
  p_languages      text[] default '{}',
  p_driving_since  int default null,
  p_photo_url      text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.drivers where id = p_driver_id;
  if v_company is null or not public.is_company_admin(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_public and not p_consent then
    raise exception 'INVALID_REQUEST' using errcode = '22023', detail = 'consent';
  end if;
  update public.drivers
  set public_profile   = p_public,
      public_bio       = nullif(trim(p_bio), ''),
      languages        = coalesce(p_languages, '{}'),
      driving_since    = p_driving_since,
      photo_url        = coalesce(p_photo_url, photo_url),
      public_consent_at = case when p_consent then coalesce(public_consent_at, now()) else null end,
      public_consent_by = case when p_consent then coalesce(public_consent_by, auth.uid()) else null end,
      profile_status   = case when p_public then 'APPROVED' else profile_status end
  where id = p_driver_id;
end;
$$;

-- ---------- ce vede clientul: poze și condiții ----------

create or replace function public._vehicle_public(p_vehicle_id uuid)
returns jsonb
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'label', v.label, 'seats', v.seats, 'year', v.manufacture_year, 'features', v.features,
    'luggage_pieces', v.luggage_pieces, 'luggage_kg', v.luggage_kg,
    'description', v.public_description,
    'photos', coalesce((select jsonb_agg(jsonb_build_object('kind', p.kind, 'url', p.url) order by
                          case p.kind when 'EXTERIOR' then 0 when 'INTERIOR' then 1 when 'LUGGAGE' then 2 else 3 end, p.sort)
                        from public.vehicle_photos p where p.vehicle_id = v.id), '[]'::jsonb)
  )
  from public.vehicles v where v.id = p_vehicle_id;
$$;

-- Site: doar microbuzele aprobate, cu poze și condiții; doar șoferii aprobați, cu acord.
create or replace function public.get_company_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := public._site_company(p_slug);
begin
  if v_company is null then
    return null;
  end if;

  return (
    select jsonb_build_object(
      'slug', c.slug, 'name', c.name, 'country', c.country,
      'locale', coalesce(cs.default_locale, 'ro'),
      'tagline', s.tagline, 'about', s.about, 'phone', s.phone, 'whatsapp', s.whatsapp, 'email', s.email,
      'address', s.address, 'logo_url', s.logo_url, 'cover_url', s.cover_url, 'accent_color', s.accent_color,
      'seo_description', s.seo_description,
      'routes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'name', rt.name, 'note', rt.public_note, 'price_from_cents', rt.price_from_cents,
          'points', (select jsonb_agg(p.name order by rtp.seq)
                     from public.route_template_points rtp join public.places p on p.id = rtp.place_id
                     where rtp.template_id = rt.id)
        ) order by rt.name)
        from public.route_templates rt where rt.company_id = c.id and rt.show_on_site), '[]'::jsonb),
      'fleet', coalesce((
        select jsonb_agg(public._vehicle_public(v.id) || jsonb_build_object(
                           'photo_url', coalesce(v.photo_url,
                             (select p.url from public.vehicle_photos p where p.vehicle_id = v.id and p.kind = 'EXTERIOR'
                              order by p.sort limit 1)),
                           'amenities', v.amenities)
                         order by v.label)
        from public.vehicles v
        where v.company_id = c.id and v.show_on_site and v.approval_status = 'APPROVED'), '[]'::jsonb),
      'drivers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'name', split_part(d.full_name, ' ', 1)
                  || coalesce(' ' || left(nullif(split_part(d.full_name, ' ', 2), ''), 1) || '.', ''),
          'bio', d.public_bio, 'photo_url', d.photo_url, 'languages', d.languages,
          'driving_since', d.driving_since
        ) order by d.full_name)
        from public.drivers d
        where d.company_id = c.id and d.active and d.public_profile and d.public_consent_at is not null
          and d.profile_status = 'APPROVED'), '[]'::jsonb),
      'posts', coalesce((
        select jsonb_agg(x order by x ->> 'published_at' desc) from (
          select jsonb_build_object('slug', sp.slug, 'title', sp.title, 'excerpt', sp.excerpt,
                                    'cover_url', sp.cover_url, 'published_at', sp.published_at) as x
          from public.site_posts sp
          where sp.company_id = c.id and sp.published_at is not null and sp.published_at <= now()
          order by sp.published_at desc limit 30) recent), '[]'::jsonb)
    )
    from public.companies c
    join public.company_sites s on s.company_id = c.id
    left join public.company_settings cs on cs.company_id = c.id
    where c.id = v_company
  );
end;
$$;

-- Linkul de urmărire: pozele și condițiile microbuzului care face cursa.
create or replace function public.get_tracking_vehicle(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_vehicle uuid;
begin
  if coalesce(length(p_token), 0) < 40 then
    return null;
  end if;
  select t.vehicle_id into v_vehicle
  from public.booking_tracking_tokens tt
  join public.bookings b on b.id = tt.booking_id
  join public.trips t on t.id = b.trip_id
  where tt.token_hash = public._token_hash(p_token) and tt.expires_at > now()
    and b.status not in ('CANCELLED', 'NO_SHOW')
    and public.has_feature(b.company_id, 'tracking_link');
  return case when v_vehicle is null then null else public._vehicle_public(v_vehicle) end;
end;
$$;

-- Schimbarea microbuzului pe o cursă cu rezervări: clienții sunt anunțați.
create or replace function public.trips_vehicle_changed()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_booking uuid;
  v_label   text;
begin
  select label into v_label from public.vehicles where id = new.vehicle_id;
  for v_booking in
    select id from public.bookings
    where trip_id = new.id and status in ('CONFIRMED', 'DRIVER_ASSIGNED', 'APPROACHING')
  loop
    perform public._enqueue_customer_notification(
      v_booking, 'VEHICLE_CHANGED',
      'vehicle_changed:' || v_booking || ':' || new.vehicle_id,
      jsonb_build_object('vehicle', v_label));
  end loop;
  return null;
end;
$$;

create trigger trips_vehicle_changed after update of vehicle_id on public.trips
for each row when (new.vehicle_id is distinct from old.vehicle_id)
execute function public.trips_vehicle_changed();

-- ---------- poza șoferului (Supabase Storage) ----------
-- Șoferul își încarcă poza doar în <company_id>/drivers/<user_id>/…, la firma unde e șofer.
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'objects') then
    execute $p$
      create policy "site-media: șoferul își încarcă poza" on storage.objects for insert to authenticated
      with check (bucket_id = 'site-media'
                  and (storage.foldername(name))[2] = 'drivers'
                  and (storage.foldername(name))[3] = auth.uid()::text
                  and public.company_role(((storage.foldername(name))[1])::uuid) = 'DRIVER')
    $p$;
  end if;
end $$;

-- ---------- drepturi ----------

revoke execute on function public.vehicles_guard(), public.trips_vehicle_check(), public.trips_vehicle_changed(),
  public._notify_company_owner(uuid, text, jsonb), public._vehicle_public(uuid)
  from public, anon, authenticated;
revoke execute on function public.min_vehicle_year(), public.company_can_manage_fleet(uuid),
  public.declare_vehicle_insurance(uuid, date, date, boolean),
  public.register_company(text, text, char, text, text, text, boolean),
  public.get_registration_checklist(uuid), public.submit_company_for_review(uuid),
  public.review_vehicle(uuid, boolean, text), public.review_company(uuid, boolean, text),
  public.admin_pending_companies(),
  public.update_my_driver_profile(uuid, text, text[], int, text, boolean),
  public.review_driver_profile(uuid, boolean, text),
  public.set_driver_public_profile(uuid, boolean, boolean, text, text[], int, text),
  public.get_tracking_vehicle(text), public.get_company_site(text)
  from public;
grant execute on function public.min_vehicle_year(), public.company_can_manage_fleet(uuid),
  public.declare_vehicle_insurance(uuid, date, date, boolean),
  public.register_company(text, text, char, text, text, text, boolean),
  public.get_registration_checklist(uuid), public.submit_company_for_review(uuid),
  public.review_vehicle(uuid, boolean, text), public.review_company(uuid, boolean, text),
  public.admin_pending_companies(),
  public.update_my_driver_profile(uuid, text, text[], int, text, boolean),
  public.review_driver_profile(uuid, boolean, text),
  public.set_driver_public_profile(uuid, boolean, boolean, text, text[], int, text)
  to authenticated;
revoke execute on function public.min_vehicle_year(), public.company_can_manage_fleet(uuid),
  public.declare_vehicle_insurance(uuid, date, date, boolean),
  public.register_company(text, text, char, text, text, text, boolean),
  public.get_registration_checklist(uuid), public.submit_company_for_review(uuid),
  public.review_vehicle(uuid, boolean, text), public.review_company(uuid, boolean, text),
  public.admin_pending_companies(),
  public.update_my_driver_profile(uuid, text, text[], int, text, boolean),
  public.review_driver_profile(uuid, boolean, text),
  public.set_driver_public_profile(uuid, boolean, boolean, text, text[], int, text)
  from anon;
grant execute on function public.get_tracking_vehicle(text), public.get_company_site(text) to anon, authenticated;
