-- Catalog editabil; copiile salvate pe firme nu se schimbă odată cu catalogul.
create table public.vehicle_package_catalog (
  id uuid primary key default gen_random_uuid(),
  vehicles_from int not null check(vehicles_from>=1),
  vehicles_to int not null check(vehicles_to>=vehicles_from and vehicles_to<2147483647),
  monthly_eur numeric(12,2) not null check(monthly_eur>=0),
  exclude using gist (int4range(vehicles_from,vehicles_to,'[]') with &&) deferrable initially deferred
);
insert into public.vehicle_package_catalog(vehicles_from,vehicles_to,monthly_eur)
values(1,3,130),(4,6,200),(7,10,300);
alter table public.vehicle_package_catalog enable row level security;
revoke all on public.vehicle_package_catalog from public,anon,authenticated;
grant select on public.vehicle_package_catalog to authenticated;
create policy package_catalog_read on public.vehicle_package_catalog for select to authenticated using(true);

create table public.company_vehicle_packages (
 company_id uuid primary key references public.companies(id) on delete cascade,
 declared_vehicles int not null check(declared_vehicles>=1),
 vehicles_from int not null check(vehicles_from>=1),
 vehicle_limit int not null check(vehicle_limit>=vehicles_from),
 monthly_eur numeric(12,2) not null check(monthly_eur>=0),
 updated_at timestamptz not null default now(), updated_by uuid,
 check(declared_vehicles between vehicles_from and vehicle_limit)
);
alter table public.company_vehicle_packages enable row level security;
revoke all on public.company_vehicle_packages from public,anon,authenticated;
grant select on public.company_vehicle_packages to authenticated;
create policy package_read on public.company_vehicle_packages for select to authenticated
 using(public.is_company_staff(company_id) or public.is_platform_admin());

create function public.validate_vehicle_package_catalog() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.vehicle_package_catalog) or exists(
 select 1 from (select vehicles_from,lag(vehicles_to,1,0) over(order by vehicles_from) previous_end
 from public.vehicle_package_catalog) x where vehicles_from<>previous_end+1) then
 raise exception 'PACKAGE_CATALOG_INVALID' using errcode='22023'; end if;
 return null;
end $$;
revoke all on function public.validate_vehicle_package_catalog() from public,anon,authenticated;
create constraint trigger package_catalog_contiguous after insert or update or delete on public.vehicle_package_catalog
 deferrable initially deferred for each row execute function public.validate_vehicle_package_catalog();

-- Un singur apel înlocuiește atomar catalogul; utilizatorii nu primesc DML direct.
create function public.admin_save_vehicle_packages(p_packages jsonb) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_max int;
begin
 if auth.uid() is null or not public.is_platform_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(23002500);
 if jsonb_typeof(p_packages) is distinct from 'array' or jsonb_array_length(p_packages)=0 then
 raise exception 'PACKAGE_CATALOG_INVALID' using errcode='22023'; end if;
 if exists(select 1 from jsonb_to_recordset(p_packages) x(vehicles_from int,vehicles_to int,monthly_eur numeric)
 where vehicles_from is null or vehicles_to is null or monthly_eur is null or vehicles_from<1
 or vehicles_to<vehicles_from or vehicles_to>=2147483647 or monthly_eur<0 or monthly_eur<>round(monthly_eur,2))
 or exists(select 1 from (select vehicles_from,lag(vehicles_to,1,0) over(order by vehicles_from) prev
 from jsonb_to_recordset(p_packages) x(vehicles_from int,vehicles_to int)) q where vehicles_from<>prev+1) then
 raise exception 'PACKAGE_CATALOG_INVALID' using errcode='22023'; end if;
 select max(vehicles_to) into v_max from jsonb_to_recordset(p_packages) x(vehicles_to int);
 if exists(select 1 from public.company_vehicle_packages where declared_vehicles>v_max)
 or exists(select company_id from public.vehicles group by company_id having count(*)>v_max) then
 raise exception 'PLAN_LIMIT_REACHED' using errcode='22023'; end if;
 delete from public.vehicle_package_catalog;
 insert into public.vehicle_package_catalog(vehicles_from,vehicles_to,monthly_eur)
 select vehicles_from,vehicles_to,monthly_eur from jsonb_to_recordset(p_packages)
 x(vehicles_from int,vehicles_to int,monthly_eur numeric);
end $$;
revoke all on function public.admin_save_vehicle_packages(jsonb) from public,anon;
grant execute on function public.admin_save_vehicle_packages(jsonb) to authenticated;

-- Backfill inițial; depășirea catalogului oprește migrația, nu trunchiază flota.
do $$ begin
 if exists(select company_id from public.vehicles group by company_id
 having count(*)>(select max(vehicles_to) from public.vehicle_package_catalog)) then
 raise exception 'PLAN_LIMIT_REACHED'; end if;
end $$;
insert into public.company_vehicle_packages(company_id,declared_vehicles,vehicles_from,vehicle_limit,monthly_eur)
select c.id,c.n,p.vehicles_from,p.vehicles_to,p.monthly_eur from
(select c.id,greatest(1,count(v.id))::int n from public.companies c left join public.vehicles v
on v.company_id=c.id group by c.id) c join public.vehicle_package_catalog p on c.n between p.vehicles_from and p.vehicles_to;

create function public.initialize_vehicle_package() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform pg_advisory_xact_lock_shared(23002500);
 insert into public.company_vehicle_packages(company_id,declared_vehicles,vehicles_from,vehicle_limit,monthly_eur)
 select new.id,1,vehicles_from,vehicles_to,monthly_eur from public.vehicle_package_catalog where vehicles_from=1;
 return new;
end $$;
revoke all on function public.initialize_vehicle_package() from public,anon,authenticated;
create trigger initialize_vehicle_package after insert on public.companies for each row execute function public.initialize_vehicle_package();

create function public.admin_set_company_vehicle_package(p_company_id uuid,p_declared_vehicles int,p_monthly_eur numeric)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.vehicle_package_catalog%rowtype;
begin
 if auth.uid() is null or not public.is_platform_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 perform pg_advisory_xact_lock_shared(23002500);
 perform 1 from public.companies where id=p_company_id for update;
 if not found then raise exception 'INVALID_REQUEST' using errcode='22023'; end if;
 select * into p from public.vehicle_package_catalog where p_declared_vehicles between vehicles_from and vehicles_to;
 if not found or p_monthly_eur is null or p_monthly_eur<0 or p_monthly_eur<>round(p_monthly_eur,2) then
 raise exception 'INVALID_REQUEST' using errcode='22023'; end if;
 if (select count(*) from public.vehicles where company_id=p_company_id and approval_status='APPROVED')>p.vehicles_to then
 raise exception 'PLAN_LIMIT_REACHED' using errcode='22023'; end if;
 update public.company_vehicle_packages set declared_vehicles=p_declared_vehicles,vehicles_from=p.vehicles_from,
 vehicle_limit=p.vehicles_to,monthly_eur=p_monthly_eur,updated_by=auth.uid(),updated_at=now() where company_id=p_company_id;
end $$;
revoke all on function public.admin_set_company_vehicle_package(uuid,int,numeric) from public,anon;
grant execute on function public.admin_set_company_vehicle_package(uuid,int,numeric) to authenticated;

create function public.register_company_with_package(p_name text,p_slug text,p_country char(2),p_registration_no text,
 p_license_no text,p_contact_phone text,p_accept_terms boolean,p_declared_vehicles integer,p_expected_price numeric)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare cid uuid; p public.vehicle_package_catalog%rowtype;
begin
 if auth.uid() is null then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 perform pg_advisory_xact_lock_shared(23002500);
 select * into p from public.vehicle_package_catalog where p_declared_vehicles between vehicles_from and vehicles_to;
 if not found then raise exception 'INVALID_REQUEST' using errcode='22023'; end if;
 if p_expected_price is distinct from p.monthly_eur then raise exception 'PACKAGE_PRICE_CHANGED' using errcode='22023'; end if;
 cid:=public.register_company(p_name,p_slug,p_country,p_registration_no,p_license_no,p_contact_phone,p_accept_terms);
 update public.company_vehicle_packages set declared_vehicles=p_declared_vehicles,vehicles_from=p.vehicles_from,
 vehicle_limit=p.vehicles_to,monthly_eur=p.monthly_eur,updated_by=auth.uid() where company_id=cid;
 return cid;
end $$;
revoke all on function public.register_company_with_package(text,text,char,text,text,text,boolean,int,numeric) from public,anon;
grant execute on function public.register_company_with_package(text,text,char,text,text,text,boolean,int,numeric) to authenticated;

create function public.guard_approved_vehicle_capacity() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_limit int; v_max int;
begin
 perform pg_advisory_xact_lock_shared(23002500);
 perform 1 from public.companies where id=new.company_id for update;
 select max(vehicles_to) into v_max from public.vehicle_package_catalog;
 if (tg_op='INSERT' or new.company_id is distinct from old.company_id) and
 (select count(*) from public.vehicles where company_id=new.company_id and id<>new.id)>=v_max then
 raise exception 'PLAN_LIMIT_REACHED' using errcode='22023'; end if;
 if new.approval_status='APPROVED' then
 select least(vehicle_limit,v_max) into v_limit from public.company_vehicle_packages where company_id=new.company_id;
 if v_limit is null or (select count(*) from public.vehicles where company_id=new.company_id
 and approval_status='APPROVED' and id<>new.id)>=v_limit then
 raise exception 'PLAN_LIMIT_REACHED' using errcode='22023'; end if;
 end if;
 return new;
end $$;
revoke all on function public.guard_approved_vehicle_capacity() from public,anon,authenticated;
create trigger zz_approved_vehicle_capacity before insert or update on public.vehicles
for each row execute function public.guard_approved_vehicle_capacity();

-- Verificarea autoritativă a tuturor vehiculelor declarate și a celor deja adăugate.
create function public.guard_registration_fleet_complete() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_check jsonb; v_declared int;
begin
 if new.submitted_at is null or new.submitted_at is not distinct from old.submitted_at then return new; end if;
 select declared_vehicles into v_declared from public.company_vehicle_packages where company_id=new.id;
 v_check:=public.get_registration_checklist(new.id);
 if v_declared is null or jsonb_array_length(v_check->'vehicles')<v_declared
 or exists(select 1 from jsonb_array_elements(v_check->'vehicles') v where not (v->>'complete')::boolean) then
 raise exception 'REGISTRATION_INCOMPLETE' using errcode='22023'; end if;
 return new;
end $$;
revoke all on function public.guard_registration_fleet_complete() from public,anon,authenticated;
create trigger zz_registration_fleet_complete before update of submitted_at on public.companies
for each row execute function public.guard_registration_fleet_complete();
