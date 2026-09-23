-- Ordinea opririlor stabilită de optimizare: doar în interiorul aceleiași zone.

:as_disp_a
-- patru rezervări: două urcă la Timișoara (0), una la Arad (1); coboară la Wien (4) / München (7)
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 0, 4,
       p_pickup_address => 'Timișoara, Piața Unirii', p_pickup_lat => 45.758, p_pickup_lng => 21.229, p_confirm => true) as b1 \gset
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2', 1, 0, 7,
       p_pickup_address => 'Timișoara, Calea Șagului', p_pickup_lat => 45.735, p_pickup_lng => 21.205, p_confirm => true) as b2 \gset
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 1, 7,
       p_pickup_address => 'Arad, centru', p_pickup_lat => 46.176, p_pickup_lng => 21.319, p_confirm => true) as b3 \gset
select public.auto_order_trip_stops('00000000-0000-0000-0000-0000000004a1');

select array_agg(id order by seq) as current_ids from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1') \gset
select id as p1 from public.trip_stops where booking_id = :'b1' and kind = 'PICKUP' \gset
select id as p2 from public.trip_stops where booking_id = :'b2' and kind = 'PICKUP' \gset
select id as p3 from public.trip_stops where booking_id = :'b3' and kind = 'PICKUP' \gset
select id as d1 from public.trip_stops where booking_id = :'b1' and kind = 'DROPOFF' \gset

-- primele două opriri sunt cele două preluări din Timișoara; le inversăm (permis)
select t.ok((:'current_ids'::uuid[])[1:2] @> array[:'p1'::uuid, :'p2'::uuid], 'primele opriri sunt preluările din Timișoara');
select array[(:'current_ids'::uuid[])[2], (:'current_ids'::uuid[])[1]] || (:'current_ids'::uuid[])[3:] as swapped \gset
select (:'swapped'::uuid[])[1] as first_after \gset
select public.set_trip_stop_order('00000000-0000-0000-0000-0000000004a1', :'swapped');
select t.ok((select seq from public.trip_stops where id = :'first_after') = 0,
            'preluările din aceeași zonă (Timișoara) se pot reordona');

-- preluarea din Arad înaintea celor din Timișoara: refuzat
select t.raises(format('select public.set_trip_stop_order(%L, %L)', '00000000-0000-0000-0000-0000000004a1',
  (array[:'p3'::uuid] || array(select x from unnest(:'swapped'::uuid[]) x where x <> :'p3'::uuid))::text),
  'INVALID_REQUEST', 'nu se poate lua clientul din Arad înaintea celor din Timișoara');
-- coborârea înaintea urcării: refuzat
select t.raises(format('select public.set_trip_stop_order(%L, %L)', '00000000-0000-0000-0000-0000000004a1',
  (array[:'d1'::uuid] || array(select x from unnest(:'swapped'::uuid[]) x where x <> :'d1'::uuid))::text),
  'INVALID_REQUEST', 'coborârea nu poate fi înaintea urcărilor');
-- o oprire lipsă sau dublată: refuzat
select t.raises(format('select public.set_trip_stop_order(%L, %L)', '00000000-0000-0000-0000-0000000004a1',
  (:'swapped'::uuid[])[1:2]::text), 'INVALID_REQUEST', 'toate opririle trebuie să fie în listă');
select t.raises(format('select public.set_trip_stop_order(%L, %L)', '00000000-0000-0000-0000-0000000004a1',
  (array[:'first_after'::uuid, :'first_after'::uuid] || (:'swapped'::uuid[])[3:])::text), 'INVALID_REQUEST', 'fără opriri dublate');

-- o oprire deja făcută nu se mută
:as_system
update public.trip_stops set status = 'DONE' where id = :'first_after';
:as_disp_a
select t.raises(format('select public.set_trip_stop_order(%L, %L)', '00000000-0000-0000-0000-0000000004a1', :'current_ids'),
  'INVALID_REQUEST', 'opririle deja făcute rămân pe loc');

:as_owner_b
select t.raises(format('select public.set_trip_stop_order(%L, %L)', '00000000-0000-0000-0000-0000000004a1', :'swapped'),
  'FORBIDDEN', 'altă firmă nu schimbă ordinea');
:as_driver_a
select t.raises(format('select public.set_trip_stop_order(%L, %L)', '00000000-0000-0000-0000-0000000004a1', :'swapped'),
  'FORBIDDEN', 'șoferul nu schimbă ordinea din dispecerat');

rollback;
