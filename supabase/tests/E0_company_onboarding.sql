-- Înscrierea firmei, aprobarea de către Super Admin, microbuze, profilul șoferului (migrația 2300).
-- Pregătirea datelor ca sistem; toate aserțiunile ca utilizatori autentificați.

:as_system
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000c101', 'patron-nou@test'),
  ('00000000-0000-0000-0000-00000000c102', 'alt-patron@test');
\set as_new_owner 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000c101'';'
\set as_other_owner 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000c102'';'

-- ---------- 1. înscrierea ----------
:as_new_owner
select t.raises($$select public.register_company('Transport Nou', 'transport-nou', 'RO', 'RO123', 'LIC-1', '+40700111222', false)$$,
  'INVALID_REQUEST', 'fără acceptarea termenilor nu se poate înscrie');
select t.raises($$select public.register_company('Transport Nou', 'firma-a', 'RO', 'RO123', 'LIC-1', '+40700111222', true)$$,
  'SLUG_TAKEN', 'adresa pe platformă trebuie să fie unică');
select public.register_company('Transport Nou', 'transport-nou', 'RO', 'RO123', 'LIC-1', '+40700111222', true) as cid \gset
select t.raises($$select public.register_company('A doua', 'a-doua', 'RO', 'RO9', 'LIC-9', '+40700111333', true)$$,
  'ALREADY_REGISTERED', 'un proprietar nu înscrie a doua firmă');
select t.ok((select status from public.companies where id = :'cid') = 'PENDING_VERIFICATION', 'firma nouă e în verificare');
select t.ok(public.company_role(:'cid') = 'OWNER', 'cel care se înscrie e proprietarul');
select t.ok((select terms_accepted_at is not null and contact_email = 'patron-nou@test' from public.companies where id = :'cid'),
            'acceptarea termenilor și emailul de contact sunt salvate');

-- ---------- 2. în verificare: flota da, restul nu ----------
insert into public.vehicles (id, company_id, label, plate, seats, approval_status)
values ('00000000-0000-0000-0000-0000000001c1', :'cid', 'TN-01', 'TM11NOU', 8, 'APPROVED');
select t.ok((select approval_status from public.vehicles where id = '00000000-0000-0000-0000-0000000001c1') = 'PENDING',
            'microbuzul adăugat de firmă e mereu „în verificare”, chiar dacă încearcă altfel');
select t.raises($$update public.vehicles set approval_status = 'APPROVED' where id = '00000000-0000-0000-0000-0000000001c1'$$,
  'FIELD_NOT_EDITABLE', 'firma nu își aprobă singură microbuzul');
select t.raises(format($$insert into public.drivers (company_id, full_name) values (%L, 'Șofer')$$, :'cid'),
  'row-level security', 'în verificare nu se adaugă șoferi');
select t.raises(format($$select public.save_route_template(%L, 'Rută', array(select id from public.places limit 2))$$, :'cid'),
  'row-level security', 'în verificare nu se creează rute');
select t.raises(format($$update public.companies set status = 'ACTIVE' where id = %L$$, :'cid'),
  'FIELD_NOT_EDITABLE', 'firma nu se activează singură');
select t.raises(format($$update public.companies set submitted_at = now() where id = %L$$, :'cid'),
  'FIELD_NOT_EDITABLE', 'firma nu se marchează singură „trimisă”');

-- ---------- 3. lista de verificare ----------
select t.ok(not (public.get_registration_checklist(:'cid') ->> 'ready')::boolean, 'fără microbuz complet, cererea nu e gata');
select t.raises(format('select public.submit_company_for_review(%L)', :'cid'),
  'REGISTRATION_INCOMPLETE', 'cererea incompletă nu se trimite');

update public.vehicles set manufacture_year = 2010, features = '{AC,USB,TRAILER}', luggage_pieces = 2, luggage_kg = 25
where id = '00000000-0000-0000-0000-0000000001c1';
select t.raises($$update public.vehicles set features = '{JACUZZI}' where id = '00000000-0000-0000-0000-0000000001c1'$$,
  'vehicles_features_check', 'condițiile vin doar din lista fixă');
insert into public.vehicle_photos (company_id, vehicle_id, kind, url) values
  (:'cid', '00000000-0000-0000-0000-0000000001c1', 'EXTERIOR', 'https://example.test/ext.jpg'),
  (:'cid', '00000000-0000-0000-0000-0000000001c1', 'INTERIOR', 'https://example.test/int.jpg');
select t.raises($$select public.declare_vehicle_insurance('00000000-0000-0000-0000-0000000001c1', current_date + 200, current_date + 200, false)$$,
  'INVALID_REQUEST', 'asigurarea se declară doar cu bifa de confirmare');
select t.raises($$select public.declare_vehicle_insurance('00000000-0000-0000-0000-0000000001c1', current_date - 1, current_date + 200, true)$$,
  'INVALID_REQUEST', 'RCA expirat nu poate fi declarat');
select public.declare_vehicle_insurance('00000000-0000-0000-0000-0000000001c1', current_date + 200, current_date + 150, true);
select t.ok((select insurance_declared_by from public.vehicles where id = '00000000-0000-0000-0000-0000000001c1')
            = '00000000-0000-0000-0000-00000000c101', 'declarația e salvată cu cine a făcut-o');

select public.get_registration_checklist(:'cid') as chk \gset
select t.ok((:'chk'::jsonb ->> 'ready')::boolean, 'cu un microbuz complet, cererea e gata');
select t.ok((:'chk'::jsonb -> 'vehicles' -> 0 ->> 'below_min_year')::boolean, 'microbuzul din 2010 e marcat ca mai vechi de 2012');
select public.submit_company_for_review(:'cid');
select t.ok((select submitted_at is not null from public.companies where id = :'cid'), 'cererea e trimisă');

-- ---------- 4. Super Admin ----------
select t.raises($$select * from public.admin_pending_companies()$$, 'FORBIDDEN', 'firma nu vede lista de aprobări');
select t.raises($$select public.review_vehicle('00000000-0000-0000-0000-0000000001c1', true)$$, 'FORBIDDEN', 'firma nu își aprobă microbuzul prin funcție');
select t.raises(format('select public.review_company(%L, true)', :'cid'), 'FORBIDDEN', 'firma nu se aprobă singură');

:as_superadmin
select t.ok((select below_min_year from public.admin_pending_companies() where id = :'cid') = 1,
            'Super Admin vede firma în așteptare, cu microbuzul vechi marcat');
select t.ok((select count(*) from public.vehicle_photos where company_id = :'cid') = 2, 'Super Admin vede pozele microbuzelor');
select t.ok((select count(*) from public.customers where company_id = :'cid') = 0
            and (select count(*) from public.customers) = 0, 'Super Admin tot nu vede clienții firmelor');
select t.raises(format('select public.review_company(%L, true)', :'cid'),
  'VEHICLE_NOT_APPROVED', 'firma se aprobă doar cu cel puțin un microbuz aprobat');
select t.raises($$select public.review_vehicle('00000000-0000-0000-0000-0000000001c1', false)$$,
  'INVALID_REQUEST', 'respingerea cere motiv');
select public.review_vehicle('00000000-0000-0000-0000-0000000001c1', true, 'Din 2010, dar întreținut; poze verificate telefonic.');
select public.review_company(:'cid', true);
select t.ok((select status from public.companies where id = :'cid') = 'ACTIVE', 'firma e aprobată');
select t.ok((select count(*) from public.notification_outbox) = 0, 'Super Admin nu citește coada de mesaje a firmelor');
:as_system
select t.ok((select count(*) from public.notification_outbox where company_id = :'cid' and template_key = 'COMPANY_APPROVED'
             and channel = 'EMAIL' and recipient = 'patron-nou@test') = 1, 'patronul primește emailul de aprobare');

-- ---------- 5. după aprobare ----------
:as_new_owner
insert into public.drivers (company_id, full_name) values (:'cid', 'Șofer Nou');
select t.ok((select count(*) from public.drivers where company_id = :'cid') = 1, 'firma aprobată își adaugă șoferii');
insert into public.vehicles (id, company_id, label, seats, manufacture_year)
values ('00000000-0000-0000-0000-0000000001c2', :'cid', 'TN-02', 8, 2020);
select t.ok((select approval_status from public.vehicles where id = '00000000-0000-0000-0000-0000000001c2') = 'PENDING',
            'și microbuzele noi, adăugate după aprobare, trec prin verificare');
select t.raises(format($$insert into public.trips (company_id, vehicle_id, title, departure_at)
                         values (%L, '00000000-0000-0000-0000-0000000001c2', 'Test', now() + interval '2 days')$$, :'cid'),
  'VEHICLE_NOT_APPROVED', 'un microbuz neaprobat nu face curse');
insert into public.trips (id, company_id, vehicle_id, title, departure_at)
values ('00000000-0000-0000-0000-0000000004c1', :'cid', '00000000-0000-0000-0000-0000000001c1', 'Test', now() + interval '2 days');
select t.raises(format($$insert into public.trips (company_id, vehicle_id, title, departure_at)
                         values (%L, '00000000-0000-0000-0000-0000000001c1', 'Târziu', current_date + 170)$$, :'cid'),
  'VEHICLE_INSURANCE_EXPIRED', 'nu se programează curse după expirarea asigurării declarate');
update public.vehicles set plate = 'TM99ALT' where id = '00000000-0000-0000-0000-0000000001c1';
select t.ok((select approval_status from public.vehicles where id = '00000000-0000-0000-0000-0000000001c1') = 'PENDING',
            'schimbarea numărului cere reaprobare');

-- ---------- 6. respingere și retrimitere ----------
:as_other_owner
select public.register_company('Alt Transport', 'alt-transport', 'AT', 'FN123', 'KONZ-1', '+43660000000', true) as cid2 \gset
insert into public.vehicles (id, company_id, label, seats, manufacture_year)
values ('00000000-0000-0000-0000-0000000001d1', :'cid2', 'W-01', 8, 2018);
insert into public.vehicle_photos (company_id, vehicle_id, kind, url) values
  (:'cid2', '00000000-0000-0000-0000-0000000001d1', 'EXTERIOR', 'https://example.test/a.jpg'),
  (:'cid2', '00000000-0000-0000-0000-0000000001d1', 'INTERIOR', 'https://example.test/b.jpg');
select public.declare_vehicle_insurance('00000000-0000-0000-0000-0000000001d1', current_date + 90, current_date + 90, true);
select public.submit_company_for_review(:'cid2');
:as_superadmin
select public.review_company(:'cid2', false, 'Lipsește licența de transport valabilă.');
select t.ok((select status || '|' || rejection_reason from public.companies where id = :'cid2')
            = 'REJECTED|Lipsește licența de transport valabilă.', 'respingerea păstrează motivul');
:as_system
select t.ok((select params ->> 'reason' from public.notification_outbox where company_id = :'cid2'
             and template_key = 'COMPANY_REJECTED') = 'Lipsește licența de transport valabilă.', 'emailul de respingere conține motivul');
:as_other_owner
select public.submit_company_for_review(:'cid2');
select t.ok((select status from public.companies where id = :'cid2') = 'PENDING_VERIFICATION'
            and (select rejection_reason from public.companies where id = :'cid2') is null, 'după corectare, firma retrimite cererea');

-- ---------- 7. profilul completat de șofer, aprobat de firmă ----------
:as_owner_a
insert into public.company_sites (company_id, published) values ('00000000-0000-0000-0000-0000000000a0', true);
:as_driver_a
select public.update_my_driver_profile('00000000-0000-0000-0000-0000000000a0', 'Conduc din 2010.', '{ro,de}', 2010,
                                       'https://example.test/ionut.jpg', true);
select t.ok((select profile_status from public.drivers where full_name = 'Ionuț') = 'SUBMITTED', 'profilul trimis de șofer așteaptă firma');
select t.raises($$select public.review_driver_profile('00000000-0000-0000-0000-0000000002a1', true)$$,
  'FORBIDDEN', 'șoferul nu își aprobă singur profilul');
:as_anon
select t.ok(jsonb_array_length(public.get_company_site('firma-a') -> 'drivers') = 0, 'neaprobat: nu apare pe site');
:as_disp_a
select t.raises($$select public.review_driver_profile('00000000-0000-0000-0000-0000000002a1', true)$$,
  'FORBIDDEN', 'dispecerul nu aprobă profiluri; doar proprietarul sau adminul');
:as_owner_a
select public.review_driver_profile('00000000-0000-0000-0000-0000000002a1', true);
:as_anon
select t.ok((public.get_company_site('firma-a') -> 'drivers' -> 0 ->> 'name') = 'Ionuț', 'aprobat și cu acordul lui: apare pe site');
:as_driver_a
select public.update_my_driver_profile('00000000-0000-0000-0000-0000000000a0', 'Text nou.', '{ro}', 2010, null, false);
:as_anon
select t.ok(jsonb_array_length(public.get_company_site('firma-a') -> 'drivers') = 0,
            'dacă șoferul își retrage acordul, dispare imediat de pe site');
:as_driver2_a
select t.raises($$select public.update_my_driver_profile('00000000-0000-0000-0000-0000000000b0', 'x', '{}', null, null, true)$$,
  'FORBIDDEN', 'un șofer nu scrie profil la altă firmă');

-- ---------- 8. ce vede clientul ----------
:as_system
insert into public.vehicle_photos (company_id, vehicle_id, kind, url) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000001a1', 'INTERIOR', 'https://example.test/i.jpg'),
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000001a1', 'EXTERIOR', 'https://example.test/e.jpg');
update public.vehicles set features = '{AC,WIFI}', show_on_site = true where id = '00000000-0000-0000-0000-0000000001a1';
insert into public.vehicles (company_id, label, seats, show_on_site) values ('00000000-0000-0000-0000-0000000000a0', 'NEAPROBAT', 8, true);
:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 0, 4, p_confirm => true) as b \gset
select public.create_tracking_link(:'b') as tok \gset
:as_anon
select public.get_tracking_vehicle(:'tok') as veh \gset
select t.ok((:'veh'::jsonb -> 'photos' -> 0 ->> 'kind') = 'EXTERIOR' and jsonb_array_length(:'veh'::jsonb -> 'photos') = 2,
            'clientul vede pozele microbuzului cursei, exteriorul întâi');
select t.ok((:'veh'::jsonb -> 'features') = '["AC", "WIFI"]'::jsonb and (:'veh'::jsonb ->> 'year') = '2019',
            'și condițiile și anul');
select t.ok(not (:'veh'::jsonb ? 'plate'), 'numărul de înmatriculare nu apare în datele publice ale microbuzului');
select t.ok(public.get_tracking_vehicle(repeat('x', 43)) is null, 'token greșit: nimic');
select t.ok(not exists (select 1 from jsonb_array_elements(public.get_company_site('firma-a') -> 'fleet') f
                        where f ->> 'label' = 'NEAPROBAT'), 'pe site apar doar microbuzele aprobate');

-- Schimbarea microbuzului pe cursă anunță clienții
:as_system
insert into public.vehicles (id, company_id, label, seats, approval_status) values
  ('00000000-0000-0000-0000-0000000001a9', '00000000-0000-0000-0000-0000000000a0', 'TM-09', 16, 'APPROVED');
:as_disp_a
update public.trips set vehicle_id = '00000000-0000-0000-0000-0000000001a9' where id = '00000000-0000-0000-0000-0000000004a1';
select t.ok((select count(*) from public.notification_outbox where booking_id = :'b' and template_key = 'VEHICLE_CHANGED') = 1,
            'clientul e anunțat că s-a schimbat microbuzul');

rollback;
