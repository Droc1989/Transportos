-- 1100 — Invitarea șoferilor în aplicație; modificarea și anularea curselor
--
-- Invitație: adminul firmei generează un cod de 8 caractere pentru un șofer, îl trimite
-- (WhatsApp, SMS), iar șoferul îl introduce după ce își face cont. Codul e folosit o
-- singură dată, expiră în 7 zile și în bază e salvat doar hash-ul lui.
--
-- Curse: regulile sunt în triggere, ca să se aplice indiferent dacă modificarea vine din
-- aplicație, dintr-o funcție sau din SQL direct:
--   * o cursă COMPLETED sau CANCELLED nu se mai modifică;
--   * o cursă IN_PROGRESS nu se anulează (se folosește fluxul de defecțiune/rezervă);
--   * vehiculul nu poate fi schimbat cu unul care are mai puține locuri decât cel mai
--     mare număr de loc deja ocupat;
--   * la anulare, toate rezervările active se anulează și locurile se eliberează.

create table public.driver_invites (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null,
  driver_id    uuid not null,
  code_hash    text not null unique,
  created_by   uuid,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '7 days',
  accepted_at  timestamptz,
  accepted_by  uuid,
  revoked_at   timestamptz,
  foreign key (driver_id, company_id) references public.drivers (id, company_id) on delete cascade
);
create index driver_invites_driver_idx on public.driver_invites (driver_id);

alter table public.driver_invites enable row level security;
create policy driver_invites_select on public.driver_invites for select to authenticated
  using (public.is_company_admin(company_id));
-- Scriere doar prin funcțiile de mai jos.
grant select on public.driver_invites to authenticated;
revoke insert, update, delete on public.driver_invites from authenticated;

create or replace function public._invite_code_hash(p_code text)
returns text
language sql immutable
as $$
  select encode(sha256(convert_to(upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g')), 'UTF8')), 'hex');
$$;

-- Generează codul (întors o singură dată, în clar) și anulează invitațiile vechi ale șoferului.
create or replace function public.create_driver_invite(p_driver_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company   uuid;
  v_user      uuid;
  v_alphabet  constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- fără 0/O, 1/I
  v_bytes     bytea := uuid_send(gen_random_uuid());
  v_code      text := '';
begin
  select company_id, user_id into v_company, v_user from public.drivers where id = p_driver_id;
  if v_company is null or not public.is_company_admin(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_user is not null then
    raise exception 'DRIVER_ALREADY_LINKED' using errcode = '22023';
  end if;

  for i in 0..7 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;

  update public.driver_invites set revoked_at = now()
  where driver_id = p_driver_id and accepted_at is null and revoked_at is null;

  insert into public.driver_invites (company_id, driver_id, code_hash, created_by)
  values (v_company, p_driver_id, public._invite_code_hash(v_code), auth.uid());

  return substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4);
end;
$$;

-- Șoferul, autentificat, acceptă invitația. Întoarce numele firmei.
create or replace function public.accept_driver_invite(p_code text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invite  public.driver_invites%rowtype;
  v_name    text;
begin
  if auth.uid() is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_invite from public.driver_invites
  where code_hash = public._invite_code_hash(p_code)
  for update;

  if v_invite.id is null or v_invite.revoked_at is not null or v_invite.accepted_at is not null
     or v_invite.expires_at < now() then
    raise exception 'INVITE_INVALID' using errcode = '22023';
  end if;

  update public.drivers set user_id = auth.uid()
  where id = v_invite.driver_id and user_id is null;
  if not found then
    raise exception 'DRIVER_ALREADY_LINKED' using errcode = '22023';
  end if;

  insert into public.company_members (company_id, user_id, role)
  values (v_invite.company_id, auth.uid(), 'DRIVER')
  on conflict (company_id, user_id) do nothing;

  update public.driver_invites set accepted_at = now(), accepted_by = auth.uid()
  where id = v_invite.id;

  select name into v_name from public.companies where id = v_invite.company_id;
  return v_name;
end;
$$;

-- Adminul deconectează contul unui șofer (telefon pierdut, plecat din firmă).
create or replace function public.unlink_driver_account(p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
  v_user    uuid;
begin
  select company_id, user_id into v_company, v_user from public.drivers where id = p_driver_id;
  if v_company is null or not public.is_company_admin(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_user is null then
    return;
  end if;

  update public.drivers set user_id = null where id = p_driver_id;
  delete from public.company_members
  where company_id = v_company and user_id = v_user and role = 'DRIVER';
end;
$$;

-- ---------- reguli pentru curse ----------

create or replace function public.trips_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_max_seat int;
  v_seats    int;
begin
  if old.status in ('COMPLETED', 'CANCELLED') then
    raise exception 'TRIP_CLOSED' using errcode = '22023';
  end if;
  if new.status = 'CANCELLED' and old.status = 'IN_PROGRESS' then
    raise exception 'TRIP_IN_PROGRESS' using errcode = '22023';
  end if;

  if new.vehicle_id is distinct from old.vehicle_id then
    select max(seat_no) into v_max_seat from public.booking_seats
    where trip_id = old.id and released_at is null;
    select seats into v_seats from public.vehicles where id = new.vehicle_id;
    if coalesce(v_max_seat, 0) > v_seats then
      raise exception 'VEHICLE_TOO_SMALL' using errcode = '22023',
        detail = format('needed=%s available=%s', v_max_seat, v_seats);
    end if;
  end if;

  return new;
end;
$$;

create trigger trips_guard before update on public.trips
for each row execute function public.trips_guard();

create or replace function public.trips_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.bookings
  set status = 'CANCELLED', cancel_reason = 'TRIP_CANCELLED', hold_expires_at = null
  where trip_id = new.id
    and status not in ('CANCELLED', 'COMPLETED', 'NO_SHOW', 'MISSED_PICKUP');

  update public.booking_seats set released_at = now()
  where trip_id = new.id and released_at is null;

  return null;
end;
$$;

create trigger trips_on_cancel after update of status on public.trips
for each row when (new.status = 'CANCELLED' and old.status is distinct from 'CANCELLED')
execute function public.trips_on_cancel();

-- Anulare din aplicație: întoarce câți clienți trebuie anunțați.
create or replace function public.cancel_trip(p_trip_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company  uuid;
  v_affected int;
begin
  select company_id into v_company from public.trips where id = p_trip_id for update;
  if v_company is null then
    raise exception 'TRIP_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.is_company_staff(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select count(*) into v_affected from public.bookings
  where trip_id = p_trip_id
    and status not in ('CANCELLED', 'COMPLETED', 'NO_SHOW', 'MISSED_PICKUP');

  update public.trips set status = 'CANCELLED' where id = p_trip_id;
  return v_affected;
end;
$$;

revoke execute on function public._invite_code_hash(text) from public, anon, authenticated;
revoke execute on function public.trips_guard(), public.trips_on_cancel() from public, anon, authenticated;
revoke execute on function public.create_driver_invite(uuid), public.accept_driver_invite(text),
  public.unlink_driver_account(uuid), public.cancel_trip(uuid) from public, anon;
grant execute on function public.create_driver_invite(uuid), public.accept_driver_invite(text),
  public.unlink_driver_account(uuid), public.cancel_trip(uuid) to authenticated;
