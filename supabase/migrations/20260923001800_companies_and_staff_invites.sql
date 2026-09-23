-- 1800 — Firme noi din panoul Super Admin; invitații pentru personal (proprietar, admin, dispecer)
--
-- Același mecanism ca la șoferi (ADR-0005): cod XXXX-XXXX, doar hash-ul în bază, o singură
-- folosire, expiră în 7 zile. accept_invite(code) acceptă atât invitațiile de șofer, cât și
-- pe cele de personal, ca pagina /invitatie să aibă un singur câmp.

-- Super Admin citește setările firmelor (nu conțin date personale).
drop policy company_settings_select on public.company_settings;
create policy company_settings_select on public.company_settings for select to authenticated
  using (public.is_company_member(company_id) or public.is_platform_admin());

create table public.staff_invites (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies (id) on delete cascade,
  role         public.member_role not null check (role in ('OWNER', 'ADMIN', 'DISPATCHER')),
  code_hash    text not null unique,
  created_by   uuid,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '7 days',
  accepted_at  timestamptz,
  accepted_by  uuid,
  revoked_at   timestamptz
);
alter table public.staff_invites enable row level security;
create policy staff_invites_select on public.staff_invites for select to authenticated
  using (public.is_company_admin(company_id) or public.is_platform_admin());
grant select on public.staff_invites to authenticated;
revoke insert, update, delete on public.staff_invites from authenticated;

create or replace function public._new_invite_code()
returns text
language plpgsql
volatile
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes    bytea := uuid_send(gen_random_uuid());
  v_code     text := '';
begin
  for i in 0..7 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$$;

-- Super Admin creează firma, cu abonament și setări implicite.
create or replace function public.create_company(
  p_name     text,
  p_slug     text,
  p_country  char(2),
  p_plan_id  text default 'PILOT'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  insert into public.companies (name, slug, country, status)
  values (trim(p_name), lower(trim(p_slug)), upper(p_country), 'ACTIVE')
  returning id into v_id;

  insert into public.company_settings (company_id, default_locale)
  values (v_id, case when upper(p_country) in ('AT', 'DE') then 'de' else 'ro' end);

  insert into public.company_subscriptions (company_id, plan_id, status, current_period_end)
  values (v_id, p_plan_id, (case when p_plan_id = 'PILOT' then 'TRIAL' else 'ACTIVE' end)::public.subscription_status,
          (current_date + interval '1 month')::date);
  return v_id;
end;
$$;

-- Adminul firmei (sau Super Admin) invită personal. Doar proprietarul sau Super Admin
-- pot invita un proprietar.
create or replace function public.create_staff_invite(p_company_id uuid, p_role public.member_role)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text := public._new_invite_code();
begin
  if p_role not in ('OWNER', 'ADMIN', 'DISPATCHER') then
    raise exception 'STOP_STATE_INVALID' using errcode = '22023';
  end if;
  if not (public.is_platform_admin()
          or (public.is_company_admin(p_company_id)
              and (p_role <> 'OWNER' or public.company_role(p_company_id) = 'OWNER'))) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  insert into public.staff_invites (company_id, role, code_hash, created_by)
  values (p_company_id, p_role, public._invite_code_hash(v_code), auth.uid());
  return substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4);
end;
$$;

-- Un singur punct de intrare pentru orice cod de invitație.
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
    -- nu e invitație de personal: poate e de șofer
    v_name := public.accept_driver_invite(p_code);
    return jsonb_build_object('company', v_name, 'role', 'DRIVER');
  end if;

  if v_invite.revoked_at is not null or v_invite.accepted_at is not null or v_invite.expires_at < now() then
    raise exception 'INVITE_INVALID' using errcode = '22023';
  end if;

  insert into public.company_members (company_id, user_id, role)
  values (v_invite.company_id, auth.uid(), v_invite.role)
  on conflict (company_id, user_id) do update set role = excluded.role;

  update public.staff_invites set accepted_at = now(), accepted_by = auth.uid() where id = v_invite.id;

  select name into v_name from public.companies where id = v_invite.company_id;
  return jsonb_build_object('company', v_name, 'role', v_invite.role);
end;
$$;

-- Panoul Super Admin: firmele cu abonamentul și activitatea lor, fără date despre clienți.
create or replace function public.admin_list_companies()
returns table (
  id               uuid,
  name             text,
  slug             text,
  country          char(2),
  status           text,
  plan_id          text,
  subscription     public.subscription_status,
  period_end       date,
  vehicles         int,
  billable         int,
  members          int,
  last_activity    timestamptz,
  created_at       timestamptz
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
  select c.id, c.name, c.slug, c.country, c.status, s.plan_id, s.status, s.current_period_end,
         (select count(*)::int from public.vehicles v where v.company_id = c.id),
         (select count(*)::int from public.vehicles v where v.company_id = c.id and not v.is_standby),
         (select count(*)::int from public.company_members m where m.company_id = c.id),
         (select max(a.created_at) from public.audit_log a where a.company_id = c.id),
         c.created_at
  from public.companies c
  left join public.company_subscriptions s on s.company_id = c.id
  order by c.name;
end;
$$;

revoke execute on function public._new_invite_code() from public, anon, authenticated;
revoke execute on function public.create_company(text, text, char, text),
  public.create_staff_invite(uuid, public.member_role), public.accept_invite(text),
  public.admin_list_companies() from public, anon;
grant execute on function public.create_company(text, text, char, text),
  public.create_staff_invite(uuid, public.member_role), public.accept_invite(text),
  public.admin_list_companies() to authenticated;
