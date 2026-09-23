-- 0800 — Jurnal de audit (master plan §9: preț, rezervare, cursă, acțiuni privilegiate)

create table public.audit_log (
  id          bigint generated always as identity primary key,
  company_id  uuid,
  actor_id    uuid,
  table_name  text not null,
  row_id      text,
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_data    jsonb,
  new_data    jsonb,
  created_at  timestamptz not null default now()
);
create index audit_log_company_idx on public.audit_log (company_id, created_at desc);

-- Tabelele de platformă, vizibile pentru Super Admin în jurnal.
create or replace function public._is_platform_table(p_table text)
returns boolean
language sql immutable
as $$
  select p_table in ('companies', 'company_members', 'company_subscriptions', 'company_feature_overrides');
$$;

create or replace function public.audit_row()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
begin
  insert into public.audit_log (company_id, actor_id, table_name, row_id, action, old_data, new_data)
  values (
    coalesce((v_row ->> 'company_id')::uuid,
             case when tg_table_name = 'companies' then (v_row ->> 'id')::uuid end),
    auth.uid(),
    tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'company_id'),
    tg_op,
    v_old,
    v_new
  );
  return null;
end;
$$;

create trigger audit_companies                 after insert or update or delete on public.companies                 for each row execute function public.audit_row();
create trigger audit_company_members           after insert or update or delete on public.company_members           for each row execute function public.audit_row();
create trigger audit_company_subscriptions     after insert or update or delete on public.company_subscriptions     for each row execute function public.audit_row();
create trigger audit_company_feature_overrides after insert or update or delete on public.company_feature_overrides for each row execute function public.audit_row();
create trigger audit_trips                     after insert or update or delete on public.trips                     for each row execute function public.audit_row();
create trigger audit_bookings                  after insert or update or delete on public.bookings                  for each row execute function public.audit_row();

alter table public.audit_log enable row level security;

-- Adminul firmei vede jurnalul firmei lui. Super Admin vede doar rândurile de platformă.
create policy audit_select on public.audit_log for select to authenticated
  using (
    (company_id is not null and public.is_company_admin(company_id))
    or (public.is_platform_admin() and public._is_platform_table(table_name))
  );
-- Nicio politică de scriere: rândurile intră doar prin trigger.

grant select on public.audit_log to authenticated;
revoke insert, update, delete on public.audit_log from authenticated;
revoke execute on function public.audit_row() from public;
grant execute on function public._is_platform_table(text) to authenticated;
