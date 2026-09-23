-- Notificări și detecție din GPS

:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 0, 4, p_confirm => true) as ana \gset
select t.ok((select count(*) from public.notification_outbox
             where booking_id = :'ana' and template_key = 'BOOKING_CONFIRMED') = 1,
            'rezervarea confirmată pune un mesaj în coadă');
select t.ok((select channel from public.notification_outbox where booking_id = :'ana') = 'PUSH',
            'fără pachetul SMS/WhatsApp, canalul e push');
select t.ok((select recipient from public.notification_outbox where booking_id = :'ana') = '+40700000001',
            'destinatarul e telefonul clientului');

-- Rezervare ținută, apoi confirmată: un singur mesaj, la confirmare
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         1, 5, 7) as markus \gset
select t.ok((select count(*) from public.notification_outbox where booking_id = :'markus') = 0,
            'rezervarea ținută nu trimite încă nimic');
select public.confirm_booking(:'markus');
select public.confirm_booking(:'markus');
select t.ok((select count(*) from public.notification_outbox where booking_id = :'markus') = 1,
            'confirmarea trimite un singur mesaj');

-- ---------- ETA ----------
:as_driver_a
select public.start_trip('00000000-0000-0000-0000-0000000004a1');
:as_system
update public.trip_stops set planned_at = now() + interval '25 minutes'
where booking_id = :'ana' and kind = 'PICKUP';
update public.trip_stops set planned_at = now() + interval '5 hours'
where booking_id = :'markus' and kind = 'PICKUP';

set local role service_role;
select t.ok(public.enqueue_eta_notifications() = 1, 'la 25 de minute: mesajul „ajunge în 30 de minute”');
select t.ok(public.enqueue_eta_notifications() = 0, 'a doua rulare nu dublează mesajul');
reset role;
select t.ok((select params ->> 'minutes' from public.notification_outbox
             where booking_id = :'ana' and template_key = 'PICKUP_ETA') = '30', 'pragul de 30');

update public.trip_stops set eta_at = now() + interval '8 minutes' where booking_id = :'ana' and kind = 'PICKUP';
set local role service_role;
select t.ok(public.enqueue_eta_notifications() = 1, 'la 8 minute: mesajul „ajunge în 10 minute”');
reset role;
update public.trip_stops set eta_at = now() + interval '20 minutes' where booking_id = :'ana' and kind = 'PICKUP';
set local role service_role;
select t.ok(public.enqueue_eta_notifications() = 0, 'dacă ETA crește din nou, nu mai trimite „30 de minute”');
reset role;

-- Doar workerul (service_role) folosește coada
:as_disp_a
select t.raises($$select public.enqueue_eta_notifications()$$, 'permission denied', 'dispecerul nu rulează workerul');
select t.raises($$select * from public.claim_notifications(10)$$, 'permission denied', 'dispecerul nu preia mesaje');

-- ---------- worker ----------
:as_system
set local role service_role;
select count(*) as claimed from public.claim_notifications(100) \gset
select t.ok(:claimed = 4, 'workerul preia toate mesajele de trimis');
select t.ok((select count(*) from public.claim_notifications(100)) = 0, 'un mesaj preluat nu e preluat de doi workeri');
select min(id) as first_id from public.notification_outbox \gset
select public.finish_notification(:first_id, false, 'timeout');
select t.ok((select status from public.notification_outbox where id = :first_id) = 'PENDING'
            and (select next_attempt_at > now() from public.notification_outbox where id = :first_id),
            'la eșec se reîncearcă mai târziu');
select max(id) as last_id from public.notification_outbox \gset
select public.finish_notification(:last_id, true);
select t.ok((select status from public.notification_outbox where id = :last_id) = 'SENT', 'trimis');
reset role;

-- ---------- detecție din GPS (preluarea Anei, în Timișoara: 45.7489, 21.2087) ----------
:as_driver_a
select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 45.7219, 21.2087, now() - interval '50 seconds', 60, 0, '00000000-0000-0000-0000-0000000004a1');
select t.ok((select status from public.trip_stops where booking_id = :'ana' and kind = 'PICKUP') = 'PLANNED',
            'la 3 km: încă planificată');
select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 45.7354, 21.2087, now() - interval '40 seconds', 50, 0, '00000000-0000-0000-0000-0000000004a1');
select t.ok((select status from public.trip_stops where booking_id = :'ana' and kind = 'PICKUP') = 'APPROACHING',
            'la 1,5 km: se apropie');
select t.ok((select status from public.bookings where id = :'ana') = 'APPROACHING', 'rezervarea: se apropie');
select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 45.7480, 21.2087, now() - interval '30 seconds', 20, 0, '00000000-0000-0000-0000-0000000004a1');
-- trece de punct fără ca Ana să urce
select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 45.7597, 21.2087, now() - interval '20 seconds', 40, 0, '00000000-0000-0000-0000-0000000004a1');
select t.ok((select count(*) from public.trip_events where type = 'PICKUP_AT_RISK') = 1, 'la 1,2 km după punct: preluare în pericol');
select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 45.7849, 21.2087, now() - interval '10 seconds', 70, 0, '00000000-0000-0000-0000-0000000004a1');
select t.ok((select count(*) from public.trip_events where type = 'PICKUP_MISSED') = 1, 'la 4 km după punct: preluare ratată');
select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 45.7900, 21.2087, now() - interval '5 seconds', 70, 0, '00000000-0000-0000-0000-0000000004a1');
select t.ok((select count(*) from public.trip_events where type in ('PICKUP_AT_RISK', 'PICKUP_MISSED')) = 2,
            'alertele nu se repetă la fiecare poziție');

-- O poziție veche sosită târziu (după lipsă de semnal) nu declanșează detecția
select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 45.7489, 21.2087, now() - interval '5 minutes', 0, 0, '00000000-0000-0000-0000-0000000004a1');
select t.ok((select status from public.trip_stops where booking_id = :'ana' and kind = 'PICKUP') = 'APPROACHING',
            'poziția întârziată nu marchează sosirea');

:as_disp_a
select t.ok((select count(*) from public.get_dispatch_alerts('00000000-0000-0000-0000-0000000000a0')) = 2,
            'dispecerul vede cele două alerte');

-- Șoferul se întoarce și o ia pe Ana: alertele dispar
:as_driver_a
select id as ana_pick from public.trip_stops where booking_id = :'ana' and kind = 'PICKUP' \gset
select public.mark_stop_arrived(:'ana_pick');
select t.ok((select count(*) from public.notification_outbox where booking_id = :'ana'
             and template_key = 'DRIVER_ARRIVED') = 0, 'șoferul nu vede coada de mesaje');
select public.board_passenger(:'ana_pick');
:as_disp_a
select t.ok((select count(*) from public.notification_outbox where booking_id = :'ana'
             and template_key = 'DRIVER_ARRIVED') = 1, 'clientul primește „șoferul a ajuns”');
select t.ok((select count(*) from public.get_dispatch_alerts('00000000-0000-0000-0000-0000000000a0')) = 0,
            'după urcare, alertele dispar');
:as_owner_b
select t.raises($$select * from public.get_dispatch_alerts('00000000-0000-0000-0000-0000000000a0')$$,
  'FORBIDDEN', 'Firma B nu vede alertele Firmei A');

-- ---------- anularea cursei anunță clienții ----------
:as_owner_b
select public.book_seats('00000000-0000-0000-0000-0000000004b1', '00000000-0000-0000-0000-0000000003b1',
                         1, 0, 1, p_confirm => true) as bb \gset
select public.cancel_trip('00000000-0000-0000-0000-0000000004b1');
select t.ok((select count(*) from public.notification_outbox where booking_id = :'bb'
             and template_key = 'TRIP_CANCELLED') = 1, 'clientul e anunțat că s-a anulat cursa');
select t.ok((select status from public.notification_outbox where booking_id = :'bb'
             and template_key = 'BOOKING_CONFIRMED') = 'CANCELLED',
            'confirmarea netrimisă e oprită');

rollback;
