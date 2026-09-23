-- Fluxul șoferului și SOS

:as_disp_a
-- Ana: Timișoara → Wien (2 pers.), Markus: Arad → München
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         2, 0, 4, p_confirm => true) as ana \gset
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         1, 1, 7, p_confirm => true) as markus \gset
select id as ana_pick from public.trip_stops where booking_id = :'ana' and kind = 'PICKUP' \gset
select id as ana_drop from public.trip_stops where booking_id = :'ana' and kind = 'DROPOFF' \gset
select id as markus_pick from public.trip_stops where booking_id = :'markus' and kind = 'PICKUP' \gset

-- ---------- cursele șoferului ----------
:as_driver_a
select t.ok((select count(*) from public.get_driver_trips(now(), now() + interval '2 days')) = 1,
            'șoferul își vede cursa de mâine');
select t.ok((select active_stops from public.get_driver_trips(now(), now() + interval '2 days')) = 4,
            'cu 4 opriri de făcut');
:as_driver2_a
select t.ok((select count(*) from public.get_driver_trips(now(), now() + interval '2 days')) = 0,
            'alt șofer nu vede cursa');
select t.raises($$select public.start_trip('00000000-0000-0000-0000-0000000004a1')$$,
  'FORBIDDEN', 'alt șofer nu pornește cursa');

-- ---------- pornire ----------
:as_driver_a
select t.raises(format('select public.board_passenger(%L)', :'ana_pick'),
  'STOP_STATE_INVALID', 'nu se urcă pasageri înainte de pornirea cursei');
select public.start_trip('00000000-0000-0000-0000-0000000004a1');
select public.start_trip('00000000-0000-0000-0000-0000000004a1'); -- a doua apăsare, fără efect
select t.ok((select status from public.trips where id = '00000000-0000-0000-0000-0000000004a1') = 'IN_PROGRESS',
            'cursa e pornită');
select t.ok((select status from public.vehicles where id = '00000000-0000-0000-0000-0000000001a1') = 'EN_ROUTE',
            'vehiculul e pe drum');
select t.ok((select count(*) from public.trip_events where type = 'TRIP_STARTED') = 1, 'un singur eveniment de pornire');
select t.ok((select status from public.bookings where id = :'ana') = 'DRIVER_ASSIGNED', 'rezervările au șofer');

-- ---------- urcare, coborâre ----------
select public.board_passenger(:'ana_pick');
select public.board_passenger(:'ana_pick');
select t.ok((select status from public.bookings where id = :'ana') = 'ON_BOARD', 'Ana e la bord');
select t.ok((select count(*) from public.trip_events where type = 'PASSENGER_ON_BOARD') = 1, 'un singur eveniment de urcare');
select t.raises(format('select public.complete_dropoff(%L)', :'ana_pick'),
  'STOP_STATE_INVALID', 'coborârea se marchează doar pe oprirea de coborâre');

-- ---------- nu s-a prezentat ----------
select public.mark_no_show(:'markus_pick');
select t.ok((select status from public.bookings where id = :'markus') = 'NO_SHOW', 'Markus: nu s-a prezentat');
select t.ok((select count(*) from public.trip_stops where booking_id = :'markus' and status = 'SKIPPED') = 2,
            'opririle lui Markus dispar din listă');
:as_disp_a
select t.ok(public.free_seats('00000000-0000-0000-0000-0000000004a1', 4, 7) = 8,
            'locul lui Markus se eliberează pentru restul cursei');

:as_driver_a
select public.complete_dropoff(:'ana_drop');
select t.ok((select status from public.bookings where id = :'ana') = 'COMPLETED', 'Ana a ajuns');
select t.raises(format('select public.board_passenger(%L)', :'markus_pick'),
  'STOP_STATE_INVALID', 'nu se urcă un client marcat „nu s-a prezentat”');

-- ---------- pauză ----------
select public.record_trip_event('00000000-0000-0000-0000-0000000004a1', 'BREAK_STARTED', 'pauza-000000001');
select t.ok((select status from public.vehicles where id = '00000000-0000-0000-0000-0000000001a1') = 'BREAK', 'pauză');
select public.record_trip_event('00000000-0000-0000-0000-0000000004a1', 'BREAK_ENDED', 'pauza-000000002');
select t.ok((select status from public.vehicles where id = '00000000-0000-0000-0000-0000000001a1') = 'EN_ROUTE', 'înapoi pe drum');
select t.raises($$select public.record_trip_event('00000000-0000-0000-0000-0000000004a1', 'TRIP_COMPLETED', 'x-00000000001')$$,
  'STOP_STATE_INVALID', 'evenimentele de sistem nu se trimit manual');

-- ---------- SOS ----------
-- Detecție automată: POSSIBLE, apoi „SUNT BINE”
select public.raise_emergency('00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000004a1',
       47.6, 17.7, 'AUTO', 'auto-000000001', 0) as auto1 \gset
select t.ok((select severity from public.emergency_events where id = :'auto1') = 'POSSIBLE', 'detecția automată e doar posibilă');
select public.dismiss_emergency(:'auto1');
select t.ok((select status from public.emergency_events where id = :'auto1') = 'CANCELLED', '„SUNT BINE” anulează alerta');

-- Alt semnal automat, fără răspuns → confirmat; al doilea semnal în 5 minute nu dublează alerta
select public.raise_emergency('00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000004a1',
       47.6, 17.7, 'AUTO', 'auto-000000002', 0) as auto2 \gset
select public.raise_emergency('00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000004a1',
       47.6, 17.7, 'AUTO', 'auto-000000003', 0) as auto3 \gset
select t.ok(:'auto2' = :'auto3', 'în fereastra de 5 minute nu se creează o a doua alertă');
select public.confirm_emergency(:'auto2');
select t.ok((select severity from public.emergency_events where id = :'auto2') = 'CONFIRMED', 'alerta confirmată');
select t.ok((select status from public.vehicles where id = '00000000-0000-0000-0000-0000000001a1') = 'EMERGENCY',
            'vehiculul e în urgență');
select t.ok((select count(*) from public.trip_events where type = 'INCIDENT') = 1, 'incidentul apare în cursă');
select t.ok((select count(*) from public.emergency_event_passengers) = 0, 'șoferul nu vede lista pasagerilor din alertă');

:as_disp_a
select t.ok((select count(*) from public.emergency_events where status = 'OPEN' and severity = 'CONFIRMED') = 1,
            'dispecerul vede alerta');
select public.acknowledge_emergency(:'auto2');
select t.ok((select acknowledged_at is not null from public.emergency_events where id = :'auto2'),
            'dispecerul confirmă că a văzut');
select public.resolve_emergency(:'auto2');
select t.ok((select status from public.vehicles where id = '00000000-0000-0000-0000-0000000001a1') = 'EN_ROUTE',
            'după rezolvare, vehiculul revine pe drum');

-- SOS manual cu un pasager la bord: confirmat imediat, cu lista pasagerilor
:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 4, 7, p_confirm => true) as ioana \gset
select id as ioana_pick from public.trip_stops where booking_id = :'ioana' and kind = 'PICKUP' \gset
:as_driver_a
select public.board_passenger(:'ioana_pick');
select public.raise_emergency('00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000004a1',
       48.3, 14.3, 'MANUAL', 'sos-0000000001', 90) as sos \gset
select t.ok((select severity from public.emergency_events where id = :'sos') = 'CONFIRMED', 'SOS manual e confirmat imediat');
:as_disp_a
select t.ok((select count(*) from public.emergency_event_passengers where event_id = :'sos') = 1,
            'dispecerul vede pasagerii de la bord');
:as_owner_b
select t.ok((select count(*) from public.emergency_events) = 0, 'Firma B nu vede alertele Firmei A');
select t.raises(format('select public.acknowledge_emergency(%L)', :'sos'), 'FORBIDDEN', 'Firma B nu confirmă alerta');

-- ---------- încheiere ----------
:as_driver_a
select public.complete_trip('00000000-0000-0000-0000-0000000004a1');
select t.ok((select status from public.trips where id = '00000000-0000-0000-0000-0000000004a1') = 'COMPLETED', 'cursa încheiată');
select t.ok((select status from public.bookings where id = :'ioana') = 'COMPLETED', 'cine era la bord a ajuns');

rollback;
