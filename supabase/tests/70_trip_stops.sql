-- Opririle cursei: create automat, ordonate pe traseu, mutate de dispecer
-- Cursa A: 0 Timișoara, 1 Arad, 2 Budapest, 3 Győr, 4 Wien, 5 Linz, 6 Salzburg, 7 München

:as_disp_a
-- Rezervările vin în ordine „amestecată”, ca în realitate
-- Linz → München
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         1, 5, 7, p_confirm => true) as c \gset
-- Timișoara → Wien
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 0, 4, p_confirm => true) as a \gset
-- Arad → München
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         2, 1, 7, p_confirm => true,
                         p_pickup_address => 'Arad, poarta verde') as b \gset

select t.ok((select count(*) from public.trip_stops where trip_id = '00000000-0000-0000-0000-0000000004a1') = 6,
            'fiecare rezervare creează o urcare și o coborâre');
select t.ok((select address from public.trip_stops where booking_id = :'b' and kind = 'PICKUP') = 'Arad, poarta verde',
            'adresa de preluare e copiată în oprire');

-- Ordinea pe traseu: urcare Timișoara, urcare Arad, coborâre Wien, urcare Linz, apoi coborârile din München
create temp view ord as
  select s.seq, s.kind, s.booking_id,
         row_number() over (order by s.seq) as pos
  from public.trip_stops s
  where s.trip_id = '00000000-0000-0000-0000-0000000004a1' and s.status <> 'SKIPPED';
grant select on ord to authenticated;

select t.ok((select booking_id from ord where pos = 1) = :'a' and (select kind from ord where pos = 1) = 'PICKUP',
            '1: urcare Timișoara');
select t.ok((select booking_id from ord where pos = 2) = :'b' and (select kind from ord where pos = 2) = 'PICKUP',
            '2: urcare Arad');
select t.ok((select booking_id from ord where pos = 3) = :'a' and (select kind from ord where pos = 3) = 'DROPOFF',
            '3: coborâre Wien');
select t.ok((select booking_id from ord where pos = 4) = :'c' and (select kind from ord where pos = 4) = 'PICKUP',
            '4: urcare Linz');
select t.ok((select count(*) from ord where pos in (5, 6) and kind = 'DROPOFF') = 2, '5–6: coborâri München');

-- Mutarea care pune coborârea Anei înaintea urcării ei e refuzată
select id as a_pick from public.trip_stops where booking_id = :'a' and kind = 'PICKUP' \gset
select id as a_drop from public.trip_stops where booking_id = :'a' and kind = 'DROPOFF' \gset
select id as c_pick from public.trip_stops where booking_id = :'c' and kind = 'PICKUP' \gset
select public.move_trip_stop(:'a_drop', -1);                    -- Wien înainte de Arad: încă valid
select t.ok((select booking_id from ord where pos = 2) = :'a', 'dispecerul mută o oprire mai sus');
select t.raises(format('select public.move_trip_stop(%L, -1)', :'a_drop'),
  'STOP_ORDER_INVALID', 'coborârea nu poate trece înaintea urcării aceluiași client');

-- Rezervare nouă: se inserează la locul ei pe traseu, fără să strice ordinea manuală
-- Győr → Salzburg
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 3, 6, p_confirm => true) as d \gset
select t.ok((select booking_id from ord where pos = 2) = :'a', 'ordinea manuală rămâne după o rezervare nouă');
select t.ok(
  (select seq from public.trip_stops where booking_id = :'d' and kind = 'PICKUP')
    < (select seq from public.trip_stops where booking_id = :'d' and kind = 'DROPOFF'),
  'noua rezervare are urcarea înaintea coborârii');

-- Ordonarea automată readuce ordinea pe traseu
select public.auto_order_trip_stops('00000000-0000-0000-0000-0000000004a1');
select t.ok((select booking_id from ord where pos = 2) = :'b', 'ordonarea automată: Arad din nou al doilea');
select t.ok(not exists (
  select 1 from public.trip_stops p join public.trip_stops d on d.booking_id = p.booking_id and d.kind = 'DROPOFF'
  where p.kind = 'PICKUP' and p.seq > d.seq), 'ordonarea automată păstrează urcarea înaintea coborârii');
select t.ok((select array_agg(seq order by seq) from public.trip_stops
             where trip_id = '00000000-0000-0000-0000-0000000004a1') = array[0,1,2,3,4,5,6,7],
            'numerotarea rămâne continuă');

-- Anularea unei rezervări scoate opririle ei din listă
select public.cancel_booking(:'c', 'test');
select t.ok((select count(*) from ord) = 6, 'opririle rezervării anulate nu mai apar');
select t.ok((select count(*) from public.trip_stops where booking_id = :'c' and status = 'SKIPPED') = 2,
            'opririle anulate sunt marcate SKIPPED');

-- Orele planificate
select public.set_stop_planned_times('00000000-0000-0000-0000-0000000004a1',
  array[:'a_pick'::uuid], array['2026-10-01 15:00+00'::timestamptz]) as n \gset
select t.ok(:n = 1 and (select planned_at from public.trip_stops where id = :'a_pick') = '2026-10-01 15:00+00',
            'ora planificată e salvată');

-- Oprire deja făcută nu mai poate fi mutată
:as_driver_a
select public.mark_stop_arrived(:'a_pick');
select t.raises(format('select public.move_trip_stop(%L, 1)', :'a_pick'), 'FORBIDDEN', 'șoferul nu reordonează opririle');
:as_disp_a
select t.raises(format('select public.move_trip_stop(%L, 1)', :'a_pick'),
  'STOP_ORDER_INVALID', 'oprirea la care s-a ajuns nu se mai mută');

-- Firma B nu atinge opririle Firmei A
:as_owner_b
select t.raises($$select public.auto_order_trip_stops('00000000-0000-0000-0000-0000000004a1')$$,
  'FORBIDDEN', 'Firma B nu ordonează cursa A');

-- Citirea cu coordonate: dispecerul vede opririle, cu clientul și lat/lng
:as_disp_a
select t.ok((select count(*) from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1')) = 6,
            'get_trip_stops întoarce opririle active');
select t.ok((select round(lat::numeric, 2) from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1')
             where seq = 0) = 45.75, 'coordonatele primei opriri (Timișoara)');
select t.ok((select count(*) from public.get_trip_route_points('00000000-0000-0000-0000-0000000004a1')) = 8,
            'punctele de traseu cu coordonate');
:as_owner_b
select t.ok((select count(*) from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1')) = 0,
            'Firma B nu vede opririle Firmei A');

rollback;
