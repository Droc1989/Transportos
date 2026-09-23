-- Izolarea firmelor și accesul pe roluri

-- Dispecerul A vede doar datele Firmei A
:as_disp_a
select t.ok((select count(*) from public.vehicles) = 1, 'dispecerul A vede doar vehiculul A');
select t.ok((select count(*) from public.customers) = 2, 'dispecerul A vede doar clienții A');
select t.ok((select count(*) from public.trips) = 1, 'dispecerul A vede doar cursa A');
select t.ok(not exists (select 1 from public.companies where slug = 'firma-b'), 'dispecerul A nu vede Firma B');

-- Nu poate scrie în Firma B
with changed as (
  update public.customers set full_name = 'Acces interzis'
  where id = '00000000-0000-0000-0000-0000000003b1' returning id
)
select t.ok((select count(*) from changed) = 0, 'dispecerul A nu modifică clientul B prin ID cunoscut');
with removed as (
  delete from public.customers where id = '00000000-0000-0000-0000-0000000003b1' returning id
)
select t.ok((select count(*) from removed) = 0, 'dispecerul A nu șterge clientul B prin ID cunoscut');
select t.raises(
  $$update public.customers set company_id = '00000000-0000-0000-0000-0000000000b0'
    where id = '00000000-0000-0000-0000-0000000003a2'$$,
  'row-level security', 'dispecerul nu poate transfera un client în altă firmă');

select t.raises(
  $$insert into public.vehicles (company_id, label, seats) values ('00000000-0000-0000-0000-0000000000b0', 'X-1', 8)$$,
  'row-level security', 'dispecerul A nu poate adăuga vehicul în Firma B');

-- Nu poate lega o cursă A de vehiculul B (cheie compusă pe company_id)
select t.raises(
  $$insert into public.trips (company_id, vehicle_id, title, departure_at)
    values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000001b1', 'X', now())$$,
  'foreign key', 'cursa A nu poate folosi vehiculul B');

-- Nu poate rezerva pe cursa B
select t.raises(
  $$select public.book_seats('00000000-0000-0000-0000-0000000004b1', '00000000-0000-0000-0000-0000000003b1', 1, 0, 1)$$,
  'FORBIDDEN', 'dispecerul A nu poate rezerva pe cursa B');

-- Rezervările nu se pot insera direct, doar prin book_seats
select t.raises(
  $$insert into public.bookings (company_id, trip_id, customer_id, passengers, from_seq, to_seq, hold_expires_at)
    values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000004a1',
            '00000000-0000-0000-0000-0000000003a1', 1, 0, 1, now() + interval '5 min')$$,
  'row-level security', 'rezervările nu se inserează direct');

-- Șoferul vede doar cursa lui și clienții de pe ea
:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 0, 4, p_confirm => true) as booking_id \gset

:as_driver_a
select t.ok((select count(*) from public.trips) = 1, 'șoferul vede cursa lui');
select t.ok((select count(*) from public.bookings) = 1, 'șoferul vede rezervarea de pe cursa lui');
select t.ok((select count(*) from public.customers) = 1, 'șoferul vede doar clientul de pe cursa lui (nu toți clienții)');
select t.ok((select count(*) from public.vehicle_positions) = 0, 'șoferul nu citește istoricul GPS');
select t.raises(
  $$update public.company_members set role = 'ADMIN'
    where user_id = auth.uid()$$,
  'permission denied', 'șoferul nu își poate acorda rol de admin');
:as_system
select t.ok((select role from public.company_members
  where company_id = '00000000-0000-0000-0000-0000000000a0'
    and user_id = '00000000-0000-0000-0000-00000000a003') = 'DRIVER',
  'rolul șoferului a rămas DRIVER după tentativa de escaladare');
:as_driver_a
with changed as (
  update public.customers set full_name = 'Acces interzis'
  where id = '00000000-0000-0000-0000-0000000003a1' returning id
)
select t.ok((select count(*) from changed) = 0, 'șoferul nu modifică datele clientului pe care îl poate citi');
select t.raises(
  $$select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 0, 1)$$,
  'FORBIDDEN', 'șoferul nu poate crea rezervări');

-- Alt șofer al aceleiași firme nu vede cursa lui Ionuț
:as_driver2_a
select t.ok((select count(*) from public.trips) = 0, 'alt șofer nu vede cursa');
select t.ok((select count(*) from public.customers) = 0, 'alt șofer nu vede clienți');

-- Super Admin: vede firme și abonamente, NU clienți sau rezervări
:as_superadmin
select t.ok((select count(*) from public.companies) = 2, 'Super Admin vede toate firmele');
select t.ok((select count(*) from public.company_subscriptions) = 2, 'Super Admin vede abonamentele');
select t.ok((select count(*) from public.customers) = 0, 'Super Admin nu vede clienții firmelor');
select t.ok((select count(*) from public.bookings) = 0, 'Super Admin nu vede rezervările');
select t.ok((select count(*) from public.audit_log where table_name = 'bookings') = 0, 'Super Admin nu vede auditul rezervărilor');
select t.ok((select count(*) from public.audit_log where table_name = 'companies') >= 2, 'Super Admin vede auditul firmelor');

-- Proprietarul A vede auditul rezervării
:as_owner_a
select t.ok((select count(*) from public.audit_log where table_name = 'bookings') >= 1, 'proprietarul A vede auditul rezervărilor');

-- Anonim: nimic din datele firmelor
-- Un cont autentificat fără apartenență nu primește drepturi de operator.
:as_system
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000c001', 'fara-firma@test');
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000c001';
select t.ok((select count(*) from public.customers) = 0, 'contul fără firmă nu citește clienți');
select t.ok((select count(*) from public.bookings) = 0, 'contul fără firmă nu citește rezervări');
select t.ok((select count(*) from public.company_members) = 0, 'contul fără firmă nu citește echipele');
select t.ok((select count(*) from public.trips) = 0, 'contul fără firmă nu citește cursele interne');

:as_anon
select t.raises($$select count(*) from public.customers$$, 'permission denied', 'anonimul nu citește clienți');
select t.raises($$select count(*) from public.companies$$, 'permission denied', 'anonimul nu citește firme');

rollback;
