-- Numele rezervării online are prioritate; RLS rămâne aplicat de funcția invoker.
:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 0, 4, p_confirm => true) as first_booking \gset
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 0, 4, p_confirm => true) as second_booking \gset
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 0, 4, p_confirm => true) as phone_booking \gset
:as_system
update public.bookings set client_name = 'Maria Online' where id = :'first_booking';
update public.bookings set client_name = 'Elena Online' where id = :'second_booking';
:as_disp_a
select t.ok((select count(*) from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1') where booking_id = :'first_booking' and customer_name = 'Maria Online') = 2, 'opriri Maria, nu numele din fișa comună');
select t.ok((select count(*) from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1') where booking_id = :'second_booking' and customer_name = 'Elena Online') = 2, 'opriri Elena, același telefon');
select t.ok((select count(*) from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1') where booking_id = :'phone_booking' and customer_name = 'Ana') = 2, 'rezervarea telefonică păstrează numele fișei');
:as_driver_a
select t.ok(exists(select 1 from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1') where customer_name = 'Maria Online'), 'șoferul alocat vede numele rezervării');
:as_owner_b
select t.ok((select count(*) from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1')) = 0, 'altă firmă nu vede opririle');
:as_superadmin
select t.ok((select count(*) from public.get_trip_stops('00000000-0000-0000-0000-0000000004a1')) = 0, 'Super Admin nu vede pasagerii');
rollback;
