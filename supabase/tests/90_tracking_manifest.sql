-- Link de urmărire, lista de pasageri, exportul rezervărilor

-- plecarea în mai puțin de 24 de ore, ca linkul să arate șoferul și vehiculul
:as_system
update public.trips set departure_at = now() + interval '20 hours'
where id = '00000000-0000-0000-0000-0000000004a1';

:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         2, 0, 4, p_confirm => true, p_pickup_address => 'Timișoara, Str. Exemplu 1',
                         p_pickup_notes => 'poarta verde', p_price_cents => 9000) as ana \gset
-- Markus urcă mai departe pe traseu, în Linz
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         1, 5, 7, p_confirm => true, p_price_cents => 4000) as markus \gset

-- ---------- link de urmărire ----------
select public.create_tracking_link(:'markus') as token \gset
select t.ok(length(:'token') = 43 and :'token' ~ '^[A-Za-z0-9_-]+$', 'tokenul e lung și sigur pentru URL');
select public.create_tracking_link(:'markus') as token2 \gset

:as_anon
select t.ok(public.get_tracking(:'token') is null, 'un link nou îl anulează pe cel vechi');
select t.ok(public.get_tracking('scurt') is null, 'token invalid: niciun răspuns');
select t.ok(public.get_tracking(repeat('x', 43)) is null, 'token inexistent: niciun răspuns');

select public.get_tracking(:'token2') as tr \gset
select t.ok((:'tr'::jsonb ->> 'company') = 'Firma A', 'clientul vede firma');
select t.ok((:'tr'::jsonb ->> 'trip_title') = 'Timișoara – München', 'și cursa');
select t.ok((:'tr'::jsonb -> 'vehicle_position') = 'null'::jsonb, 'poziția vehiculului nu apare înainte de cursă');
select t.ok((:'tr'::jsonb ->> 'driver_first_name') = 'Ionuț', 'cu o zi înainte vede prenumele șoferului');
select t.ok((:'tr'::jsonb ->> 'stops_before')::int = 2, 'Markus vede câte opriri sunt înaintea lui');
select t.ok(not (:'tr'::jsonb ? 'customer_phone') and position('Ana' in :'tr') = 0,
            'linkul nu arată date despre alți clienți');

-- În cursă: poziția apare când microbuzul e aproape (Ana a coborât → Markus e următorul)
:as_system
update public.trips set status = 'IN_PROGRESS' where id = '00000000-0000-0000-0000-0000000004a1';
insert into public.vehicle_positions_current (vehicle_id, company_id, trip_id, location, speed_kmh, recorded_at)
values ('00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000000a0',
        '00000000-0000-0000-0000-0000000004a1', st_setsrid(st_makepoint(16.2, 48.2), 4326)::geography, 90, now());
update public.bookings set status = 'COMPLETED' where id = :'ana';
update public.trip_stops set status = 'DONE' where booking_id = :'ana';

:as_anon
select public.get_tracking(:'token2') as tr \gset
select t.ok((:'tr'::jsonb ->> 'stops_before')::int = 0, 'nicio oprire înaintea lui Markus');
select t.ok(round((:'tr'::jsonb -> 'vehicle_position' ->> 'lng')::numeric, 1) = 16.2,
            'microbuzul aproape: clientul vede poziția exactă');

-- Rezervarea anulată nu mai arată nimic despre vehicul
:as_system
update public.bookings set status = 'CANCELLED' where id = :'markus';
:as_anon
select public.get_tracking(:'token2') as tr \gset
select t.ok((:'tr'::jsonb -> 'vehicle_position') = 'null'::jsonb and (:'tr'::jsonb -> 'vehicle') = 'null'::jsonb,
            'rezervare anulată: fără vehicul și poziție');

-- Linkul fără funcția tracking_link nu mai răspunde
:as_system
insert into public.company_feature_overrides (company_id, feature_key, enabled)
values ('00000000-0000-0000-0000-0000000000a0', 'tracking_link', false);
:as_anon
select t.ok(public.get_tracking(:'token2') is null, 'fără funcția din plan, linkul nu mai merge');
select t.raises($$select public.create_tracking_link('00000000-0000-0000-0000-000000000000')$$,
  'permission denied', 'anonimul nu creează linkuri');
:as_disp_a
select t.raises(format('select public.create_tracking_link(%L)', :'ana'),
  'FEATURE_NOT_ENABLED', 'fără funcția din plan nu se creează linkuri');

-- ---------- lista de pasageri ----------
:as_system
delete from public.company_feature_overrides where feature_key = 'tracking_link';
update public.bookings set status = 'CONFIRMED' where id in (:'ana', :'markus');
:as_driver_a
select t.ok((select count(*) from public.get_passenger_manifest('00000000-0000-0000-0000-0000000004a1')) = 2,
            'șoferul vede lista de pasageri a cursei lui');
select t.ok((select seats from public.get_passenger_manifest('00000000-0000-0000-0000-0000000004a1')
             where full_name = 'Ana') = array[1, 2], 'cu locurile Anei');
select t.ok((select from_name || '–' || to_name from public.get_passenger_manifest('00000000-0000-0000-0000-0000000004a1')
             where full_name = 'Markus') = 'Linz–München', 'și porțiunea fiecăruia');
:as_driver2_a
select t.raises($$select * from public.get_passenger_manifest('00000000-0000-0000-0000-0000000004a1')$$,
  'FORBIDDEN', 'alt șofer nu vede lista');

-- ---------- export ----------
:as_disp_a
select t.ok((select count(*) from public.export_bookings('00000000-0000-0000-0000-0000000000a0',
             now(), now() + interval '7 days')) = 2, 'exportul conține rezervările perioadei');
select t.ok((select sum(price_cents) from public.export_bookings('00000000-0000-0000-0000-0000000000a0',
             now(), now() + interval '7 days')) = 13000, 'cu prețurile');
:as_owner_b
select t.raises($$select * from public.export_bookings('00000000-0000-0000-0000-0000000000a0', now(), now() + interval '7 days')$$,
  'FORBIDDEN', 'Firma B nu exportă datele Firmei A');

rollback;
