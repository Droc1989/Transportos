-- Buget comun tuturor instanțelor: cel mult 40 de apeluri externe de adrese în 60 s.
-- Fără IP-uri sau adrese personale stocate; acces doar prin RPC-ul serverului.
create schema if not exists private_geocoding;
revoke all on schema private_geocoding from public, anon, authenticated;
create table private_geocoding.budget (
  id boolean primary key default true check (id),
  hits timestamptz[] not null default '{}'
);
alter table private_geocoding.budget enable row level security;
revoke all on private_geocoding.budget from public, anon, authenticated, service_role;
insert into private_geocoding.budget(id) values (true);

create function public.consume_address_budget()
returns boolean language plpgsql security definer
set search_path = pg_catalog, private_geocoding, pg_temp
as $$
declare
  v_hits timestamptz[];
  v_now timestamptz;
begin
  select hits into v_hits from private_geocoding.budget where id = true for update;
  v_now := clock_timestamp();
  select coalesce(array_agg(h), '{}'::timestamptz[]) into v_hits
  from unnest(v_hits) h where h > v_now - interval '60 seconds';
  if cardinality(v_hits) >= 40 then return false; end if;
  update private_geocoding.budget set hits = array_append(v_hits, v_now) where id = true;
  return true;
end;
$$;
revoke all on function public.consume_address_budget() from public, anon, authenticated;
grant execute on function public.consume_address_budget() to service_role;
