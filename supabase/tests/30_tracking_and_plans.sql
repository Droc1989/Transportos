-- Poziții GPS, funcții pe plan, mod „doar citire”, sosirea la oprire

-- ---------- poziții ----------
:as_driver_a
select t.ok(public.ingest_position('00000000-0000-0000-0000-0000000001a1', 46.19, 21.31,
       now() - interval '1 minute', 88, 300, '00000000-0000-0000-0000-0000000004a1'), 'șoferul trimite poziția');
select t.ok(not public.ingest_position('00000000-0000-0000-0000-0000000001a1', 46.19, 21.31,
       now() - interval '1 minute', 88, 300, '00000000-0000-0000-0000-0000000004a1'), 'aceeași poziție de două ori e ignorată');
-- o poziție mai veche, primită târziu (după lipsă de semnal), nu suprascrie poziția curentă
select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 45.75, 21.21,
       now() - interval '10 minutes', 70, 300, '00000000-0000-0000-0000-0000000004a1');
select t.ok((select round(st_y(location::geometry)::numeric, 2) from public.vehicle_positions_current
             where vehicle_id = '00000000-0000-0000-0000-0000000001a1') = 46.19,
            'poziția curentă rămâne cea mai nouă');
select t.raises(
  $$select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 46.19, 21.31,
         now() + interval '1 hour', 88, 300, '00000000-0000-0000-0000-0000000004a1')$$,
  'INVALID_POSITION', 'poziție din viitor refuzată');

:as_driver2_a
select t.raises(
  $$select public.ingest_position('00000000-0000-0000-0000-0000000001a1', 46.19, 21.31, now(), 88, 300,
         '00000000-0000-0000-0000-0000000004a1')$$,
  'FORBIDDEN', 'alt șofer nu poate trimite poziții pentru cursa asta');

:as_owner_b
select t.ok((select count(*) from public.vehicle_positions_current) = 0, 'Firma B nu vede pozițiile Firmei A');

-- ---------- funcții pe plan ----------
:as_owner_a
select t.ok(public.has_feature('00000000-0000-0000-0000-0000000000a0', 'bookings'), 'Start include rezervări');
select t.ok(not public.has_feature('00000000-0000-0000-0000-0000000000a0', 'eta_traffic_notifications'),
            'Start nu include ETA cu trafic');
select t.raises(
  $$insert into public.company_feature_overrides (company_id, feature_key, enabled)
    values ('00000000-0000-0000-0000-0000000000a0', 'eta_traffic_notifications', true)$$,
  'row-level security', 'firma nu își poate porni singură funcții');

:as_superadmin
insert into public.company_feature_overrides (company_id, feature_key, enabled, reason, set_by)
values ('00000000-0000-0000-0000-0000000000a0', 'eta_traffic_notifications', true, 'pilot',
        '00000000-0000-0000-0000-00000000f001');
select t.ok(public.has_feature('00000000-0000-0000-0000-0000000000a0', 'eta_traffic_notifications'),
            'Super Admin pornește funcția pentru firmă');

-- ---------- mod „doar citire” la restanță ----------
update public.company_subscriptions set status = 'READ_ONLY'
where company_id = '00000000-0000-0000-0000-0000000000a0';

:as_disp_a
select t.raises(
  $$select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 0, 1)$$,
  'COMPANY_READ_ONLY', 'în mod doar citire nu se fac rezervări noi');
select t.ok((select count(*) from public.trips) = 1, 'în mod doar citire datele rămân vizibile');

:as_driver_a
select t.ok(public.ingest_position('00000000-0000-0000-0000-0000000001a1', 47.50, 19.04,
       now() - interval '5 seconds', 95, 290, '00000000-0000-0000-0000-0000000004a1'),
       'cursa începută continuă și în mod doar citire');

-- ---------- sosirea la oprire ----------
:as_superadmin
update public.company_subscriptions set status = 'ACTIVE'
where company_id = '00000000-0000-0000-0000-0000000000a0';

:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 1, 4, p_confirm => true) as b \gset
-- oprirea de urcare e creată automat odată cu rezervarea
select id as stop from public.trip_stops where booking_id = :'b' and kind = 'PICKUP' \gset

:as_driver_a
select public.mark_stop_arrived(:'stop');
select public.mark_stop_arrived(:'stop'); -- a doua apăsare, fără efect
select t.ok((select status from public.trip_stops where id = :'stop') = 'ARRIVED',
            'oprirea e marcată ARRIVED');
select t.ok((select status from public.bookings where id = :'b') = 'ARRIVED', 'rezervarea devine ARRIVED');
select t.ok((select count(*) from public.trip_events where type = 'ARRIVED_AT_PICKUP') = 1,
            'evenimentul de sosire apare o singură dată');

rollback;
