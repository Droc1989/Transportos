-- Date de test comune. Fiecare fișier de test rulează după acesta, în aceeași
-- tranzacție, și se termină cu ROLLBACK: testele nu se influențează între ele.
begin;

create schema t;
grant usage on schema t to authenticated, anon, service_role;

create function t.ok(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'TEST EȘUAT: %', p_msg;
  end if;
end $$;

-- Rulează SQL și cere să eșueze cu un mesaj care conține p_expected.
create function t.raises(p_sql text, p_expected text, p_msg text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if position(p_expected in sqlerrm) > 0 then
      return;
    end if;
    raise exception 'TEST EȘUAT: % (eroare primită: %)', p_msg, sqlerrm;
  end;
  raise exception 'TEST EȘUAT: % (nu a apărut nicio eroare)', p_msg;
end $$;

grant execute on all functions in schema t to authenticated, anon, service_role;

-- Utilizatori
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000a001', 'owner-a@test'),
  ('00000000-0000-0000-0000-00000000a002', 'dispecer-a@test'),
  ('00000000-0000-0000-0000-00000000a003', 'sofer-a@test'),
  ('00000000-0000-0000-0000-00000000a004', 'sofer2-a@test'),
  ('00000000-0000-0000-0000-00000000b001', 'owner-b@test'),
  ('00000000-0000-0000-0000-00000000f001', 'superadmin@test');

insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-00000000f001');

-- Firme
insert into public.companies (id, name, slug, country, status) values
  ('00000000-0000-0000-0000-0000000000a0', 'Firma A', 'firma-a', 'RO', 'ACTIVE'),
  ('00000000-0000-0000-0000-0000000000b0', 'Firma B', 'firma-b', 'RO', 'ACTIVE');
insert into public.company_settings (company_id, show_on_public_map) values
  ('00000000-0000-0000-0000-0000000000a0', true),
  ('00000000-0000-0000-0000-0000000000b0', false);
insert into public.company_subscriptions (company_id, plan_id, status) values
  ('00000000-0000-0000-0000-0000000000a0', 'START', 'ACTIVE'),
  ('00000000-0000-0000-0000-0000000000b0', 'START', 'ACTIVE');

insert into public.company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'OWNER'),
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a002', 'DISPATCHER'),
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a003', 'DRIVER'),
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a004', 'DRIVER'),
  ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-00000000b001', 'OWNER');

-- Flotă (Firma A: microbuz 8 locuri; Firma B: 8 locuri)
insert into public.vehicles (id, company_id, label, plate, seats) values
  ('00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000000a0', 'TM-01', 'TM01AAA', 8),
  ('00000000-0000-0000-0000-0000000001b1', '00000000-0000-0000-0000-0000000000b0', 'AR-01', 'AR01BBB', 8);
-- microbuze aprobate de platformă, cu an și asigurări declarate (migrația 2300)
update public.vehicles set approval_status = 'APPROVED', manufacture_year = 2019,
       rca_valid_until = current_date + 300, passenger_insurance_until = current_date + 300,
       insurance_declared_at = now();

insert into public.drivers (id, company_id, user_id, full_name) values
  ('00000000-0000-0000-0000-0000000002a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a003', 'Ionuț'),
  ('00000000-0000-0000-0000-0000000002a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a004', 'Florin');

insert into public.customers (id, company_id, full_name, phone) values
  ('00000000-0000-0000-0000-0000000003a1', '00000000-0000-0000-0000-0000000000a0', 'Ana', '+40700000001'),
  ('00000000-0000-0000-0000-0000000003a2', '00000000-0000-0000-0000-0000000000a0', 'Markus', '+49150000002'),
  ('00000000-0000-0000-0000-0000000003b1', '00000000-0000-0000-0000-0000000000b0', 'Client B', '+40700000009');

-- Cursa Firmei A: Timișoara → München, șofer Ionuț
insert into public.trips (id, company_id, vehicle_id, driver_id, title, departure_at) values
  ('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000000a0',
   '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000002a1',
   'Timișoara – München', now() + interval '1 day');

insert into public.trip_route_points (trip_id, company_id, seq, name, location)
select '00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000000a0', seq, name,
       st_setsrid(st_makepoint(lng, lat), 4326)::geography
from (values
  (0, 'Timișoara', 45.7489, 21.2087),
  (1, 'Arad',      46.1866, 21.3123),
  (2, 'Budapest',  47.4979, 19.0402),
  (3, 'Győr',      47.6875, 17.6504),
  (4, 'Wien',      48.2082, 16.3738),
  (5, 'Linz',      48.3069, 14.2858),
  (6, 'Salzburg',  47.8095, 13.0550),
  (7, 'München',   48.1351, 11.5820)
) as p(seq, name, lat, lng);

-- Cursa Firmei B
insert into public.trips (id, company_id, vehicle_id, title, departure_at) values
  ('00000000-0000-0000-0000-0000000004b1', '00000000-0000-0000-0000-0000000000b0',
   '00000000-0000-0000-0000-0000000001b1', 'Arad – Wien', now() + interval '1 day');
insert into public.trip_route_points (trip_id, company_id, seq, name, location) values
  ('00000000-0000-0000-0000-0000000004b1', '00000000-0000-0000-0000-0000000000b0', 0, 'Arad',
   st_setsrid(st_makepoint(21.3123, 46.1866), 4326)::geography),
  ('00000000-0000-0000-0000-0000000004b1', '00000000-0000-0000-0000-0000000000b0', 1, 'Wien',
   st_setsrid(st_makepoint(16.3738, 48.2082), 4326)::geography);

-- Scurtături pentru a schimba utilizatorul curent (în interiorul tranzacției).
\set as_owner_a 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000a001'';'
\set as_disp_a 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000a002'';'
\set as_driver_a 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000a003'';'
\set as_driver2_a 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000a004'';'
\set as_owner_b 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000b001'';'
\set as_superadmin 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000f001'';'
\set as_anon 'set local role anon; set local "request.jwt.claim.sub" = '''';'
\set as_system 'reset role; set local "request.jwt.claim.sub" = '''';'
