-- Marketplace: căutare publică, rezervarea clientului, plăți direct la firmă (migrația 2400).
-- Pregătirea ca sistem; aserțiunile ca utilizatori autentificați, anonim sau service_role.

:as_system
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000cc01', 'client1@test'),
  ('00000000-0000-0000-0000-00000000cc02', 'client2@test');
-- Prețuri pe porțiuni pentru cursa A (Timișoara 0 … Wien 4, Linz 5 … München 7), pe persoană
insert into public.route_templates (id, company_id, name) values
  ('00000000-0000-0000-0000-0000000006a1', '00000000-0000-0000-0000-0000000000a0', 'Timișoara – München');
insert into public.route_template_prices (template_id, company_id, from_seq, to_seq, price_cents) values
  ('00000000-0000-0000-0000-0000000006a1', '00000000-0000-0000-0000-0000000000a0', 0, 7, 10000),
  ('00000000-0000-0000-0000-0000000006a1', '00000000-0000-0000-0000-0000000000a0', 1, 7, 9500),
  ('00000000-0000-0000-0000-0000000006a1', '00000000-0000-0000-0000-0000000000a0', 5, 7, 3000);
update public.trips set template_id = '00000000-0000-0000-0000-0000000006a1'
where id = '00000000-0000-0000-0000-0000000004a1';

\set as_client1 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000cc01'';'
\set as_client2 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000cc02'';'
\set as_service 'set local role service_role; set local "request.jwt.claim.sub" = '''';'

-- ---------- 1. căutarea publică ----------
:as_anon
select t.ok((select count(*) from public.search_marketplace(46.19, 21.31, 48.14, 11.58, 2, now(), now() + interval '3 days')
             where company_name = 'Firma A' and from_name = 'Arad' and to_name = 'München' and price_cents = 9500
               and free_seats = 8 and not online_payment and accepts_cash) = 1,
            'vizitatorul găsește cursa Arad → München, cu prețul pe persoană și locurile libere');
select t.ok((select vehicle ? 'photos' and not (vehicle ? 'plate')
             from public.search_marketplace(46.19, 21.31, 48.14, 11.58, 2, now(), now() + interval '3 days') limit 1),
            'rezultatul arată microbuzul (poze, condiții), fără număr de înmatriculare');
select t.ok((select count(distinct company_name) from public.search_marketplace(46.19, 21.31, 48.21, 16.37, 1, now(), now() + interval '3 days')) = 2,
            'Arad → Wien: apar ambele firme, clientul alege');
select t.ok(not exists (select 1 from public.search_marketplace(48.14, 11.58, 46.19, 21.31, 1, now(), now() + interval '3 days')),
            'sensul invers nu găsește cursa');

select t.ok((select price_cents || '|' || from_name || '|' || to_name
             from public.get_marketplace_offer('00000000-0000-0000-0000-0000000004a1', 1, 7, 2)) = '9500|Arad|München',
            'pagina de rezervare citește oferta cursei');
select t.ok((select count(*) from public.places) > 30 and (select round(lat::numeric, 2) from public.public_places() where name = 'Wien') = 48.21,
            'vizitatorul vede lista de orașe, cu coordonate, pentru căutare');
select t.raises($$select count(*) from public.trips$$, 'permission denied', 'dar nu cursele direct din tabel');

-- Ordonare neutră: cursa care pleacă mai devreme e prima, indiferent de firmă
:as_system
update public.trips set departure_at = now() + interval '20 hours' where id = '00000000-0000-0000-0000-0000000004b1';
:as_anon
select t.ok((select company_name from public.search_marketplace(46.19, 21.31, 48.21, 16.37, 1, now(), now() + interval '3 days') limit 1) = 'Firma B',
            'ordinea e după ora plecării, nu după firmă');

-- Firmă suspendată, microbuz neaprobat, plecare în mai puțin de 30 de minute: nu apar
:as_system
update public.companies set status = 'SUSPENDED' where slug = 'firma-b';
:as_anon
select t.ok(not exists (select 1 from public.search_marketplace(46.19, 21.31, 48.21, 16.37, 1, now(), now() + interval '3 days')
                        where company_name = 'Firma B'), 'firma suspendată nu apare în căutare');
:as_system
update public.companies set status = 'ACTIVE' where slug = 'firma-b';
update public.vehicles set approval_status = 'PENDING' where label = 'AR-01';
:as_anon
select t.ok(not exists (select 1 from public.search_marketplace(46.19, 21.31, 48.21, 16.37, 1, now(), now() + interval '3 days')
                        where company_name = 'Firma B'), 'cursa cu microbuz neaprobat nu apare');
:as_system
update public.vehicles set approval_status = 'APPROVED' where label = 'AR-01';
update public.trips set departure_at = now() + interval '10 minutes' where id = '00000000-0000-0000-0000-0000000004b1';
:as_anon
select t.ok(not exists (select 1 from public.search_marketplace(46.19, 21.31, 48.21, 16.37, 1, now(), now() + interval '3 days')
                        where company_name = 'Firma B'), 'cursa care pleacă în mai puțin de 30 de minute nu mai apare');

-- ---------- 2. rezervarea clientului, numerar ----------
:as_client1
select t.raises($$select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 7, 2, 'Arad, Str. X', null, 'CASH', 'k1-cash-0001')$$,
  'PROFILE_REQUIRED', 'fără profil (nume, telefon) clientul nu poate rezerva');
insert into public.client_profiles (user_id, full_name, phone) values ('00000000-0000-0000-0000-00000000cc01', 'Elena Client', '+40711000001');
select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 7, 2, 'Arad, Str. X', 'poarta albastră', 'CASH', 'k1-cash-0001') as r1 \gset
select (:'r1'::jsonb ->> 'booking_id') as cash_booking \gset
select t.ok((select status || '|' || source || '|' || price_cents from public.bookings where id = :'cash_booking')
            = 'CONFIRMED|MARKETPLACE|19000', 'rezervarea cu plata la șofer e confirmată; prețul: 2 × 95 €');
select t.ok((public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 7, 2, 'Arad', null, 'CASH', 'k1-cash-0001') ->> 'repeated')::boolean,
            'dubla apăsare întoarce aceeași rezervare');
select t.ok((select count(*) from public.my_bookings()) = 1, 'clientul își vede rezervarea');
select t.ok((select count(*) from public.bookings) = 1 and (select count(*) from public.customers) = 1,
            'clientul vede doar rezervarea și fișa lui');
select t.raises($$select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 7, 1, 'Arad', null, 'FULL', 'k1-full-0001')$$,
  'PAYMENT_OPTION_NOT_AVAILABLE', 'fără Stripe conectat, plata online nu e disponibilă');

-- ---------- 3. firma își conectează Stripe (doar prin webhook) ----------
:as_owner_a
select t.raises($$insert into public.company_payment_settings (company_id, stripe_account_id, stripe_charges_enabled)
                  values ('00000000-0000-0000-0000-0000000000a0', 'acct_fals', true)$$,
  'permission denied', 'firma nu își scrie singură contul Stripe (îl confirmă Stripe)');
insert into public.company_payment_settings (company_id, deposit_percent, cancel_until_hours)
values ('00000000-0000-0000-0000-0000000000a0', 20, 48);
:as_client1
select t.raises($$select public.set_company_stripe_account('00000000-0000-0000-0000-0000000000a0', 'acct_123', true)$$,
  'permission denied', 'nimeni în afară de webhook nu setează contul Stripe');
:as_service
select public.set_company_stripe_account('00000000-0000-0000-0000-0000000000a0', 'acct_1FirmaA', true);

-- ---------- 4. avans online ----------
:as_client1
select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 5, 7, 2, 'Linz', null, 'DEPOSIT', 'k1-dep-00001') as r2 \gset
select (:'r2'::jsonb ->> 'booking_id') as dep_booking, (:'r2'::jsonb ->> 'payment_id') as dep_payment \gset
select t.ok((:'r2'::jsonb ->> 'amount_due_now_cents')::int = 1200 and (:'r2'::jsonb ->> 'stripe_account_id') = 'acct_1FirmaA',
            'avansul: 20% din 2 × 30 € = 12 €, plătit în contul Stripe al firmei');
select t.ok((select status from public.bookings where id = :'dep_booking') = 'HELD', 'locul e ținut cât clientul plătește');
:as_client2
select t.raises(format('select public.attach_payment_session(%L, %L)', :'dep_payment', 'cs_test_alt_client'),
  'FORBIDDEN', 'alt client nu atașează sesiunea de plată');
:as_client1
select public.attach_payment_session(:'dep_payment', 'cs_test_deposit_0001');
select t.raises(format('select public.attach_payment_session(%L, %L)', :'dep_payment', 'cs_test_a_doua_oara'),
  'FORBIDDEN', 'sesiunea se atașează o singură dată');
select t.raises($$select public.mark_payment_paid('cs_test_deposit_0001', 1200)$$, 'permission denied', 'clientul nu își marchează singur plata');

:as_service
select t.raises($$select public.mark_payment_paid('cs_test_deposit_0001', 999)$$, 'PAYMENT_MISMATCH', 'suma greșită e refuzată');
select t.ok(public.mark_payment_paid('cs_test_deposit_0001', 1200) = 'CONFIRMED', 'plata confirmată de Stripe confirmă rezervarea');
select t.ok(public.mark_payment_paid('cs_test_deposit_0001', 1200) = 'ALREADY_PAID', 'webhook-ul repetat nu dublează plata');
:as_system
select t.ok((select payment_status || '|' || amount_paid_cents from public.bookings where id = :'dep_booking') = 'DEPOSIT_PAID|1200',
            'rezervarea: avans plătit, 12 €');

-- ---------- 5. restul la destinație ----------
:as_driver_a
select t.ok((select amount_due_cents from public.get_passenger_manifest('00000000-0000-0000-0000-0000000004a1')
             where booking_id = :'dep_booking') = 4800, 'șoferul vede că are de încasat 48 €');
select t.raises(format('select public.record_cash_payment(%L, 5000, %L)', :'dep_booking', 'cash-k1-0001'),
  'PAYMENT_MISMATCH', 'nu se poate încasa mai mult decât restul');
select public.record_cash_payment(:'dep_booking', 4800, 'cash-k1-0001');
select public.record_cash_payment(:'dep_booking', 4800, 'cash-k1-0001');
:as_system
select t.ok((select payment_status || '|' || amount_paid_cents from public.bookings where id = :'dep_booking') = 'PAID|6000',
            'restul încasat o singură dată: plătit integral');

-- ---------- 6. plata care expiră și plata întârziată ----------
:as_client1
select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 0, 7, 1, 'Timișoara', null, 'FULL', 'k1-full-0002') as r3 \gset
select public.attach_payment_session((:'r3'::jsonb ->> 'payment_id')::uuid, 'cs_test_full_expired');
:as_service
select public.mark_payment_expired('cs_test_full_expired');
:as_system
select t.ok((select status || '|' || cancel_reason from public.bookings where id = (:'r3'::jsonb ->> 'booking_id')::uuid)
            = 'CANCELLED|PAYMENT_EXPIRED', 'sesiunea de plată expirată anulează rezervarea');
select t.ok((select count(*) from public.booking_seats where booking_id = (:'r3'::jsonb ->> 'booking_id')::uuid and released_at is null) = 0,
            'și eliberează locul');

:as_client1
select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 0, 7, 1, 'Timișoara', null, 'FULL', 'k1-full-0003') as r4 \gset
select public.attach_payment_session((:'r4'::jsonb ->> 'payment_id')::uuid, 'cs_test_full_late01');
:as_system
update public.bookings set hold_expires_at = now() - interval '1 minute' where id = (:'r4'::jsonb ->> 'booking_id')::uuid;
select public._release_expired_holds('00000000-0000-0000-0000-0000000004a1');
:as_service
select t.ok(public.mark_payment_paid('cs_test_full_late01', 10000) = 'LATE_PAYMENT',
            'plata sosită după expirarea locului e semnalată pentru rambursare');
:as_system
select t.ok((select late from public.payments where provider_ref = 'cs_test_full_late01'), 'plata e marcată „întârziată”');

-- ---------- 7. preț lipsă și opțiuni ale firmei ----------
:as_client1
select t.raises($$select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 4, 1, 'Arad', null, 'FULL', 'k1-noprice-01')$$,
  'PRICE_NOT_SET', 'fără preț pe porțiune, plata online nu se poate');
:as_owner_a
update public.company_payment_settings set accepts_cash = false where company_id = '00000000-0000-0000-0000-0000000000a0';
:as_client1
select t.raises($$select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 4, 1, 'Arad', null, 'CASH', 'k1-nocash-001')$$,
  'PAYMENT_OPTION_NOT_AVAILABLE', 'firma care nu acceptă numerar nu primește rezervări cu plata la șofer');

-- ---------- 8. telefonul altcuiva ----------
:as_client2
insert into public.client_profiles (user_id, full_name, phone) values ('00000000-0000-0000-0000-00000000cc02', 'Ana', '+40700000001');
:as_owner_a
update public.company_payment_settings set accepts_cash = true where company_id = '00000000-0000-0000-0000-0000000000a0';
:as_client2
select t.raises($$select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 7, 1, 'Arad', null, 'CASH', 'k2-cash-0001')$$,
  'PHONE_NOT_VERIFIED', 'fișa existentă a firmei nu se leagă de un cont cu telefon neconfirmat');
:as_system
update auth.users set phone = '40700000001', phone_confirmed_at = now() where id = '00000000-0000-0000-0000-00000000cc02';
:as_client2
select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 7, 1, 'Arad', null, 'CASH', 'k2-cash-0002');
select t.ok((select user_id from public.customers where phone = '+40700000001') = '00000000-0000-0000-0000-00000000cc02',
            'cu telefonul confirmat, fișa se leagă de cont');
select t.ok((select count(*) from public.my_bookings()) = 1 and not exists (select 1 from public.my_bookings() where passengers = 2),
            'clientul 2 nu vede rezervările clientului 1');

-- ---------- 9. anularea de către client ----------
:as_client1
select t.raises(format('select public.client_cancel_booking(%L)', :'cash_booking'),
  'CANCELLATION_TOO_LATE', 'cu regula firmei de 48 h, anularea cu o zi înainte nu se mai poate online');
:as_owner_a
update public.company_payment_settings set cancel_until_hours = 2 where company_id = '00000000-0000-0000-0000-0000000000a0';
:as_client1
select public.client_cancel_booking(:'cash_booking');
select t.ok((select status from public.bookings where id = :'cash_booking') = 'CANCELLED', 'clientul își anulează rezervarea în termen');
:as_client2
select t.raises(format('select public.client_cancel_booking(%L)', :'dep_booking'), 'FORBIDDEN', 'nu anulezi rezervarea altcuiva');
select t.raises(format('select public.client_tracking_link(%L)', :'dep_booking'), 'FORBIDDEN', 'nici linkul de urmărire al altcuiva');
:as_client1
select t.ok(length(public.client_tracking_link(:'dep_booking')) = 43, 'clientul își ia linkul de urmărire');

-- ---------- 10. firmele și Super Admin ----------
:as_disp_a
select t.ok((select count(*) from public.bookings where source = 'MARKETPLACE') >= 4, 'dispecerul vede rezervările venite din căutare');
select t.ok((select count(*) from public.payments) >= 3, 'și plățile');
:as_owner_b
select t.ok((select count(*) from public.payments) = 0, 'Firma B nu vede plățile Firmei A');
:as_superadmin
select t.ok((select count(*) from public.payments) = 0 and (select count(*) from public.client_profiles) = 0,
            'Super Admin nu vede plăți sau profiluri de clienți');

rollback;
