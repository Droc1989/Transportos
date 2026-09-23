-- Invitarea șoferilor; anularea și modificarea curselor

:as_system
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000c001', 'sofer-nou@test'),
  ('00000000-0000-0000-0000-00000000c002', 'altcineva@test');
insert into public.drivers (id, company_id, full_name) values
  ('00000000-0000-0000-0000-0000000002a9', '00000000-0000-0000-0000-0000000000a0', 'Radu');

-- ---------- invitații ----------

-- Dispecerul nu poate invita, doar proprietarul/adminul
:as_disp_a
select t.raises($$select public.create_driver_invite('00000000-0000-0000-0000-0000000002a9')$$,
  'FORBIDDEN', 'dispecerul nu poate genera invitații');

-- Adminul altei firme nu poate invita șoferii Firmei A
:as_owner_b
select t.raises($$select public.create_driver_invite('00000000-0000-0000-0000-0000000002a9')$$,
  'FORBIDDEN', 'Firma B nu invită șoferii Firmei A');

:as_owner_a
select public.create_driver_invite('00000000-0000-0000-0000-0000000002a9') as old_code \gset
select public.create_driver_invite('00000000-0000-0000-0000-0000000002a9') as code \gset
select t.ok(:'code' ~ '^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$', 'codul are forma XXXX-XXXX, fără 0/O/1/I');
select t.ok((select count(*) from public.driver_invites where revoked_at is null) = 1,
            'un cod nou îl anulează pe cel vechi');
select t.ok(not exists (select 1 from public.driver_invites where code_hash like '%' || replace(:'code', '-', '') || '%'),
            'în bază e salvat doar hash-ul codului');
select t.raises($$select public.create_driver_invite('00000000-0000-0000-0000-0000000002a1')$$,
  'DRIVER_ALREADY_LINKED', 'nu se invită un șofer care are deja cont');

-- Șoferul nou acceptă
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000c001';
select t.raises(format('select public.accept_driver_invite(%L)', :'old_code'),
  'INVITE_INVALID', 'codul vechi nu mai merge');
select t.raises($$select public.accept_driver_invite('AAAA-BBBB')$$, 'INVITE_INVALID', 'cod greșit refuzat');
select t.ok(public.accept_driver_invite(lower(replace(:'code', '-', ' '))) = 'Firma A',
            'codul merge și scris cu litere mici sau cu spațiu');
select t.ok((select user_id from public.drivers where id = '00000000-0000-0000-0000-0000000002a9')
            = '00000000-0000-0000-0000-00000000c001', 'șoferul e legat de cont');
select t.ok((select role from public.company_members
             where user_id = '00000000-0000-0000-0000-00000000c001') = 'DRIVER', 'devine membru DRIVER');

-- Codul se folosește o singură dată
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000c002';
select t.raises(format('select public.accept_driver_invite(%L)', :'code'),
  'INVITE_INVALID', 'codul nu poate fi folosit a doua oară');

-- Cod expirat
:as_owner_a
select public.unlink_driver_account('00000000-0000-0000-0000-0000000002a9');
select t.ok((select user_id from public.drivers where id = '00000000-0000-0000-0000-0000000002a9') is null,
            'adminul deconectează contul șoferului');
select t.ok(not exists (select 1 from public.company_members
                        where user_id = '00000000-0000-0000-0000-00000000c001'), 'și îi scoate accesul');
select public.create_driver_invite('00000000-0000-0000-0000-0000000002a9') as code2 \gset
:as_system
update public.driver_invites set expires_at = now() - interval '1 minute' where accepted_at is null and revoked_at is null;
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000c002';
select t.raises(format('select public.accept_driver_invite(%L)', :'code2'), 'INVITE_INVALID', 'cod expirat refuzat');

-- Anonimul nu poate accepta invitații
:as_anon
select t.raises(format('select public.accept_driver_invite(%L)', :'code2'), 'permission denied', 'anonimul nu acceptă');

-- ---------- curse: anulare ----------

:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         3, 0, 7, p_confirm => true) as b1 \gset
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a2',
                         1, 2, 5) as b2 \gset

-- Vehicul mai mic decât locurile deja ocupate (4 locuri ocupate, vehicul nou cu 3)
:as_system
insert into public.vehicles (id, company_id, label, seats, approval_status) values
  ('00000000-0000-0000-0000-0000000001a3', '00000000-0000-0000-0000-0000000000a0', 'TM-03', 3, 'APPROVED'),
  ('00000000-0000-0000-0000-0000000001a4', '00000000-0000-0000-0000-0000000000a0', 'TM-04', 16, 'APPROVED');
:as_disp_a
select t.raises($$update public.trips set vehicle_id = '00000000-0000-0000-0000-0000000001a3'
                  where id = '00000000-0000-0000-0000-0000000004a1'$$,
  'VEHICLE_TOO_SMALL', 'nu se schimbă pe un vehicul prea mic');
update public.trips set vehicle_id = '00000000-0000-0000-0000-0000000001a4',
                        departure_at = departure_at + interval '1 hour'
where id = '00000000-0000-0000-0000-0000000004a1';
select t.ok((select vehicle_id from public.trips where id = '00000000-0000-0000-0000-0000000004a1')
            = '00000000-0000-0000-0000-0000000001a4', 'schimbarea pe un vehicul mai mare merge');
-- 16 locuri minus 4 ocupate pe toată cursa (3 ale Anei + 1 al lui Markus pe Budapest–Linz)
select t.ok(public.free_seats('00000000-0000-0000-0000-0000000004a1', 0, 7) = 12,
            'locurile libere se recalculează după noul vehicul');

select t.ok(public.cancel_trip('00000000-0000-0000-0000-0000000004a1') = 2, 'anularea întoarce 2 clienți de anunțat');
select t.ok((select count(*) from public.bookings where trip_id = '00000000-0000-0000-0000-0000000004a1'
             and status = 'CANCELLED' and cancel_reason = 'TRIP_CANCELLED') = 2, 'rezervările sunt anulate');
select t.ok((select count(*) from public.booking_seats where trip_id = '00000000-0000-0000-0000-0000000004a1'
             and released_at is null) = 0, 'locurile sunt eliberate');
select t.raises($$update public.trips set departure_at = now() where id = '00000000-0000-0000-0000-0000000004a1'$$,
  'TRIP_CLOSED', 'o cursă anulată nu se mai modifică');
select t.raises($$select public.book_seats('00000000-0000-0000-0000-0000000004a1',
                  '00000000-0000-0000-0000-0000000003a1', 1, 0, 1)$$,
  'TRIP_CLOSED', 'pe o cursă anulată nu se mai rezervă');

-- O cursă în desfășurare nu se anulează
:as_system
update public.trips set status = 'IN_PROGRESS' where id = '00000000-0000-0000-0000-0000000004b1';
:as_owner_b
select t.raises($$select public.cancel_trip('00000000-0000-0000-0000-0000000004b1')$$,
  'TRIP_IN_PROGRESS', 'cursa pornită nu se anulează');

-- Firma B nu anulează cursele Firmei A
select t.raises($$select public.cancel_trip('00000000-0000-0000-0000-0000000004a1')$$,
  'FORBIDDEN', 'Firma B nu anulează cursele Firmei A');

rollback;
