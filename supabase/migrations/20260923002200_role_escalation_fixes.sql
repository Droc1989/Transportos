-- 2200 — Închiderea căilor de escaladare a drepturilor în interiorul unei firme
--
-- Găsite la verificarea fundației (etapa 1 din TransportOS-etape.md), reproduse pe main:
--   1. un ADMIN își putea schimba singur rolul în OWNER sau adăuga direct orice cont ca membru
--      (politica company_members_write permitea orice scriere adminului);
--   2. adminul firmei putea modifica `status`, `slug` și `country` ale firmei, deci o firmă
--      suspendată de Super Admin se putea reactiva singură;
--   3. adminul putea scrie direct `drivers.user_id` (legarea unui cont fără invitație) și
--      câmpurile de acord pentru profilul public.
--
-- Reguli noi:
--   * membrii se modifică doar prin change_member_role / remove_member (și prin invitații);
--   * nimeni nu își schimbă propriul rol; doar un OWNER (sau Super Admin) atinge rolul OWNER;
--     firma păstrează mereu cel puțin un OWNER;
--   * o invitație nu schimbă rolul cuiva care e deja membru (nici în sus, nici în jos);
--   * la firmă, personalul poate schimba doar numele; status/slug/country doar Super Admin;
--   * la șofer, personalul scrie doar nume, telefon și activ; contul și acordul trec prin funcții;
--   * accesul șoferului la curse cere și apartenența DRIVER la firmă, nu doar drivers.user_id.
--
-- Coduri de eroare noi: CANNOT_CHANGE_OWN_ROLE, OWNER_REQUIRED, LAST_OWNER, ALREADY_MEMBER,
-- NOT_MEMBER, FIELD_NOT_EDITABLE.

-- ---------- 1. membri: fără scriere directă ----------

drop policy if exists company_members_write on public.company_members;
revoke insert, update, delete on public.company_members from authenticated;

create or replace function public._owner_count(p_company uuid)
returns int
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::int from public.company_members where company_id = p_company and role = 'OWNER';
$$;

create or replace function public.change_member_role(p_company_id uuid, p_user_id uuid, p_role public.member_role)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_current public.member_role;
  v_is_platform boolean := public.is_platform_admin();
begin
  if not (v_is_platform or public.is_company_admin(p_company_id)) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_CHANGE_OWN_ROLE' using errcode = '42501';
  end if;
  if p_role not in ('OWNER', 'ADMIN', 'DISPATCHER') then
    -- șoferii intră și ies doar prin invitația de șofer / deconectare
    raise exception 'FIELD_NOT_EDITABLE' using errcode = '22023';
  end if;

  -- blochează membrii firmei, ca două schimbări simultane să nu lase firma fără OWNER
  perform 1 from public.company_members where company_id = p_company_id for update;
  select role into v_current from public.company_members where company_id = p_company_id and user_id = p_user_id;
  if v_current is null then
    raise exception 'NOT_MEMBER' using errcode = 'P0002';
  end if;
  if v_current = 'DRIVER' then
    raise exception 'FIELD_NOT_EDITABLE' using errcode = '22023';
  end if;
  if (v_current = 'OWNER' or p_role = 'OWNER')
     and not (v_is_platform or public.company_role(p_company_id) = 'OWNER') then
    raise exception 'OWNER_REQUIRED' using errcode = '42501';
  end if;
  if v_current = 'OWNER' and p_role <> 'OWNER' and public._owner_count(p_company_id) <= 1 then
    raise exception 'LAST_OWNER' using errcode = '22023';
  end if;

  update public.company_members set role = p_role where company_id = p_company_id and user_id = p_user_id;
end;
$$;

create or replace function public.remove_member(p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_current public.member_role;
  v_is_platform boolean := public.is_platform_admin();
  v_self boolean := p_user_id = auth.uid();
begin
  -- oricine poate pleca singur dintr-o firmă; pe alții îi scoate doar adminul
  if not (v_self or v_is_platform or public.is_company_admin(p_company_id)) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  perform 1 from public.company_members where company_id = p_company_id for update;
  select role into v_current from public.company_members where company_id = p_company_id and user_id = p_user_id;
  if v_current is null then
    raise exception 'NOT_MEMBER' using errcode = 'P0002';
  end if;
  if v_current = 'OWNER' and not v_self and not (v_is_platform or public.company_role(p_company_id) = 'OWNER') then
    raise exception 'OWNER_REQUIRED' using errcode = '42501';
  end if;
  if v_current = 'OWNER' and public._owner_count(p_company_id) <= 1 then
    raise exception 'LAST_OWNER' using errcode = '22023';
  end if;

  delete from public.company_members where company_id = p_company_id and user_id = p_user_id;
  -- dacă era șofer, contul nu mai e legat de fișa lui
  update public.drivers set user_id = null where company_id = p_company_id and user_id = p_user_id;
end;
$$;

-- O invitație nu schimbă rolul unui membru existent.
create or replace function public.accept_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invite public.staff_invites%rowtype;
  v_name   text;
begin
  if auth.uid() is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_invite from public.staff_invites
  where code_hash = public._invite_code_hash(p_code)
  for update;

  if v_invite.id is null then
    v_name := public.accept_driver_invite(p_code);
    return jsonb_build_object('company', v_name, 'role', 'DRIVER');
  end if;

  if v_invite.revoked_at is not null or v_invite.accepted_at is not null or v_invite.expires_at < now() then
    raise exception 'INVITE_INVALID' using errcode = '22023';
  end if;
  if exists (select 1 from public.company_members where company_id = v_invite.company_id and user_id = auth.uid()) then
    raise exception 'ALREADY_MEMBER' using errcode = '22023';
  end if;

  insert into public.company_members (company_id, user_id, role)
  values (v_invite.company_id, auth.uid(), v_invite.role);
  update public.staff_invites set accepted_at = now(), accepted_by = auth.uid() where id = v_invite.id;

  select name into v_name from public.companies where id = v_invite.company_id;
  return jsonb_build_object('company', v_name, 'role', v_invite.role);
end;
$$;

-- Invitația de șofer: la fel, nu schimbă rolul unui membru existent al firmei.
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
  if exists (select 1 from public.company_members
             where company_id = v_invite.company_id and user_id = auth.uid() and role <> 'DRIVER') then
    raise exception 'ALREADY_MEMBER' using errcode = '22023';
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

-- ---------- 2. firma: câmpurile de platformă doar pentru Super Admin ----------

create or replace function public.companies_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Se aplică cererilor utilizatorilor (JWT cu sub). Migrațiile, jobul de sistem și
  -- funcțiile de platformă nu au utilizator final.
  if auth.uid() is not null and not public.is_platform_admin()
     and (new.status is distinct from old.status
          or new.slug is distinct from old.slug
          or new.country is distinct from old.country
          or new.id is distinct from old.id) then
    raise exception 'FIELD_NOT_EDITABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger companies_guard before update on public.companies
for each row execute function public.companies_guard();

-- ---------- 3. șoferi: contul și acordul doar prin funcții ----------

revoke insert, update on public.drivers from authenticated;
grant insert (id, company_id, full_name, phone, active) on public.drivers to authenticated;
grant update (full_name, phone, active) on public.drivers to authenticated;

-- Accesul la cursă cere legătura de cont ȘI apartenența DRIVER la firmă.
create or replace function public.is_trip_driver(p_trip uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.trips t
    join public.drivers d on d.id = t.driver_id and d.company_id = t.company_id
    join public.company_members m on m.company_id = d.company_id and m.user_id = d.user_id and m.role = 'DRIVER'
    where t.id = p_trip and d.user_id = auth.uid() and d.active
  );
$$;

-- ---------- drepturi ----------

revoke execute on function public._owner_count(uuid), public.companies_guard() from public, anon, authenticated;
revoke execute on function public.change_member_role(uuid, uuid, public.member_role),
  public.remove_member(uuid, uuid) from public, anon;
grant execute on function public.change_member_role(uuid, uuid, public.member_role),
  public.remove_member(uuid, uuid) to authenticated;
revoke execute on function public.accept_invite(text), public.accept_driver_invite(text) from public, anon;
grant execute on function public.accept_invite(text), public.accept_driver_invite(text) to authenticated;
