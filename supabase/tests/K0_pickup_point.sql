-- Punctul exact de preluare, setat de client pentru rezervarea lui online.

:as_system
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000cd01', 'client-adresa@test'),
                                          ('00000000-0000-0000-0000-00000000cd02', 'alt-client@test');
\set as_c1 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000cd01'';'
\set as_c2 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000cd02'';'

:as_c1
insert into public.client_profiles (user_id, full_name, phone) values ('00000000-0000-0000-0000-00000000cd01', 'Client Adresă', '+40711999001');
select public.book_marketplace('00000000-0000-0000-0000-0000000004a1', 1, 7, 1, 'Arad, Str. Test 1', null, 'CASH', 'cd1-cash-0001') ->> 'booking_id' as b \gset

-- Arad, pe traseu: acceptat
select public.set_my_pickup_point(:'b', 46.176, 21.319);
:as_system
select t.ok((select round(st_y(pickup_location::geometry)::numeric, 3) from public.bookings where id = :'b') = 46.176,
            'clientul își setează punctul exact de preluare, pe traseu');

:as_c1
select t.raises(format('select public.set_my_pickup_point(%L, 48.8566, 2.3522)', :'b'),
  'INVALID_REQUEST', 'un punct departe de traseu (Paris) e refuzat');
:as_c2
select t.raises(format('select public.set_my_pickup_point(%L, 46.18, 21.32)', :'b'),
  'FORBIDDEN', 'alt client nu schimbă preluarea rezervării mele');
:as_disp_a
select t.raises(format('select public.set_my_pickup_point(%L, 46.18, 21.32)', :'b'),
  'FORBIDDEN', 'funcția e doar pentru client (dispecerul setează punctul la rezervare)');
:as_anon
select t.raises(format('select public.set_my_pickup_point(%L, 46.18, 21.32)', :'b'),
  'permission denied', 'vizitatorii nu au acces');

-- după pornirea cursei: nu se mai schimbă
:as_system
update public.trips set status = 'IN_PROGRESS' where id = '00000000-0000-0000-0000-0000000004a1';
:as_c1
select t.raises(format('select public.set_my_pickup_point(%L, 46.177, 21.318)', :'b'),
  'TRIP_CLOSED', 'după plecare, punctul de preluare nu se mai schimbă');

rollback;
