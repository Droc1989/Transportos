-- Locuri pe segmente, rezervări ținute, idempotență, potrivire curse
-- Cursa A: 8 locuri, puncte 0 Timișoara … 4 Wien, 5 Linz … 7 München

:as_disp_a

-- Ana: Timișoara → Wien (segmentele 0–4), confirmată
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 0, 4, p_confirm => true) as ana \gset

-- Markus: Linz → München (5–7) poate primi ACELAȘI loc 1, pentru că nu se suprapune
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         1, 5, 7, p_confirm => true) as markus \gset
select t.ok(
  (select seat_no from public.booking_seats where booking_id = :'markus') = 1,
  'Markus primește locul 1, liber după Wien');

-- Porțiunea Wien → Linz rămâne cu 8 locuri libere, Timișoara → Wien cu 7
select t.ok(public.free_seats('00000000-0000-0000-0000-0000000004a1', 4, 5) = 8, 'Wien–Linz: 8 libere');
select t.ok(public.free_seats('00000000-0000-0000-0000-0000000004a1', 0, 4) = 7, 'Timișoara–Wien: 7 libere');
select t.ok(public.free_seats('00000000-0000-0000-0000-0000000004a1', 0, 7) = 7, 'toată cursa: 7 libere');

-- Grup de 7 pe toată cursa încape, al 8-lea nu mai încape
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         7, 0, 7, p_confirm => true) as grup \gset
select t.raises(
  $$select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2', 1, 2, 3)$$,
  'NOT_ENOUGH_SEATS', 'cursa plină pe Budapest–Győr refuză rezervarea');

-- Wien → Linz are încă un loc liber (locul 1 e liber între Ana și Markus)
select t.ok(public.free_seats('00000000-0000-0000-0000-0000000004a1', 4, 5) = 1, 'Wien–Linz: 1 liber');

-- Anularea eliberează locurile
select public.cancel_booking(:'grup', 'test');
select t.ok(public.free_seats('00000000-0000-0000-0000-0000000004a1', 0, 7) = 7, 'după anulare: 7 libere');
select public.cancel_booking(:'grup', 'din nou'); -- idempotent, fără eroare

-- Segment invalid
select t.raises(
  $$select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 5, 2)$$,
  'INVALID_SEGMENT', 'direcție inversă refuzată');
select t.raises(
  $$select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1', 1, 0, 9)$$,
  'INVALID_SEGMENT', 'punct inexistent refuzat');

-- Idempotență: aceeași cheie întoarce aceeași rezervare, fără locuri în plus
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         2, 1, 3, p_idempotency_key => 'tel-123') as idem1 \gset
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         2, 1, 3, p_idempotency_key => 'tel-123') as idem2 \gset
select t.ok(:'idem1' = :'idem2', 'aceeași cheie, aceeași rezervare');
select t.ok((select count(*) from public.booking_seats where booking_id = :'idem1') = 2, 'fără locuri dublate');

-- Rezervare ținută (HELD) care expiră își eliberează locurile
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         5, 0, 7) as held \gset
select t.ok((select status from public.bookings where id = :'held') = 'HELD', 'rezervarea e ținută');
:as_system
update public.bookings set hold_expires_at = now() - interval '1 minute' where id = :'held';
:as_disp_a
select t.ok(public.free_seats('00000000-0000-0000-0000-0000000004a1', 0, 7) >= 5, 'expirată: locurile se văd libere');
select t.raises(format('select public.confirm_booking(%L)', :'held'), 'HOLD_EXPIRED',
  'nu se poate confirma o rezervare expirată');
-- Următoarea rezervare pe cursă face curățenie: expirata devine CANCELLED
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         1, 6, 7, p_confirm => true) is not null as cleanup \gset
select t.ok((select status from public.bookings where id = :'held') = 'CANCELLED', 'expirata devine CANCELLED');
select t.ok((select cancel_reason from public.bookings where id = :'held') = 'HOLD_EXPIRED', 'motiv HOLD_EXPIRED');

-- Confirmarea unei rezervări ținute, valabile
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 2, 4) as held2 \gset
select t.ok(public.confirm_booking(:'held2') = 'CONFIRMED', 'confirmare reușită');
select t.ok(public.confirm_booking(:'held2') = 'CONFIRMED', 'confirmarea e idempotentă');

-- Potrivire: client în Arad → München, în direcția cursei
select t.ok(exists (
  select 1 from public.find_matching_trips(46.19, 21.31, 48.14, 11.58, 1,
                                           now(), now() + interval '2 days')
  where trip_id = '00000000-0000-0000-0000-0000000004a1' and from_name = 'Arad' and to_name = 'München'
), 'Arad → München găsește cursa A');

-- Potrivire în sens invers (München → Arad) nu găsește cursa
select t.ok(not exists (
  select 1 from public.find_matching_trips(48.14, 11.58, 46.19, 21.31, 1,
                                           now(), now() + interval '2 days')
), 'sensul invers nu găsește cursa');

-- Adresă departe de traseu (Cluj) nu găsește cursa
select t.ok(not exists (
  select 1 from public.find_matching_trips(46.77, 23.60, 48.14, 11.58, 1,
                                           now(), now() + interval '2 days')
), 'Cluj e prea departe de traseu');

-- Firma B nu vede cursa A în potrivire (RLS)
:as_owner_b
select t.ok(not exists (
  select 1 from public.find_matching_trips(46.19, 21.31, 48.14, 11.58, 1,
                                           now(), now() + interval '2 days')
  where trip_id = '00000000-0000-0000-0000-0000000004a1'
), 'Firma B nu vede cursa A');

-- Plasa de siguranță: chiar și ca superuser, două rânduri active pe același loc
-- și segmente suprapuse sunt respinse de baza de date.
:as_system
select t.raises(format($$
  insert into public.booking_seats (booking_id, company_id, trip_id, seat_no, segment)
  values (%L, '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000004a1', 1, int4range(2, 3))
$$, :'held2'), 'booking_seats_no_overlap', 'constrângerea de excludere blochează dublarea');

rollback;
