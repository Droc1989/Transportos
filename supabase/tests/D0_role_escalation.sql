-- Escaladarea drepturilor în interiorul aceleiași firme (migrația 2200).
-- Datele se pregătesc ca sistem; toate aserțiunile rulează ca utilizatori autentificați.

:as_system
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000e001', 'admin-a@test'),
  ('00000000-0000-0000-0000-00000000e002', 'al-doilea-owner-a@test');
insert into public.company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e001', 'ADMIN');

\set as_admin_a 'set local role authenticated; set local "request.jwt.claim.sub" = ''00000000-0000-0000-0000-00000000e001'';'

-- ---------- membri: fără scriere directă ----------
:as_admin_a
select t.raises($$update public.company_members set role = 'OWNER' where user_id = '00000000-0000-0000-0000-00000000e001'$$,
  'permission denied', 'adminul nu își poate ridica rolul direct în tabel');
select t.raises($$insert into public.company_members (company_id, user_id, role)
                  values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e002', 'OWNER')$$,
  'permission denied', 'adminul nu poate adăuga membri direct, ocolind invitațiile');
select t.raises($$delete from public.company_members where user_id = '00000000-0000-0000-0000-00000000a001'$$,
  'permission denied', 'adminul nu poate șterge direct proprietarul');

-- ---------- change_member_role ----------
select t.raises($$select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e001', 'OWNER')$$,
  'CANNOT_CHANGE_OWN_ROLE', 'nimeni nu își schimbă propriul rol');
select t.raises($$select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a002', 'OWNER')$$,
  'OWNER_REQUIRED', 'adminul nu poate numi un proprietar');
select t.raises($$select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'DISPATCHER')$$,
  'OWNER_REQUIRED', 'adminul nu poate retrograda proprietarul');
select t.raises($$select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a003', 'DISPATCHER')$$,
  'FIELD_NOT_EDITABLE', 'un șofer nu devine personal prin schimbare de rol');
select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a002', 'ADMIN');
select t.ok((select role from public.company_members where user_id = '00000000-0000-0000-0000-00000000a002') = 'ADMIN',
            'adminul poate face din dispecer admin');

:as_system
update public.company_members set role = 'DISPATCHER' where user_id = '00000000-0000-0000-0000-00000000a002';
:as_disp_a
select t.raises($$select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e001', 'DISPATCHER')$$,
  'FORBIDDEN', 'dispecerul nu schimbă rolurile altora');

-- ---------- ultimul proprietar ----------
:as_owner_a
select t.raises($$select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'ADMIN')$$,
  'CANNOT_CHANGE_OWN_ROLE', 'proprietarul nu se retrogradează singur');
select t.raises($$select public.remove_member('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001')$$,
  'LAST_OWNER', 'ultimul proprietar nu poate pleca');
select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e001', 'OWNER');
:as_system
select t.ok((select count(*) from public.company_members where company_id = '00000000-0000-0000-0000-0000000000a0'
             and role = 'OWNER') = 2, 'proprietarul poate numi alt proprietar');
:as_owner_a
select public.remove_member('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001');
:as_system
select t.ok((select count(*) from public.company_members where company_id = '00000000-0000-0000-0000-0000000000a0'
             and role = 'OWNER') = 1, 'cu doi proprietari, unul poate pleca');

-- ---------- invitațiile nu schimbă rolul membrilor existenți ----------
:as_admin_a
select public.create_staff_invite('00000000-0000-0000-0000-0000000000a0', 'DISPATCHER') as code \gset
select t.raises(format('select public.accept_invite(%L)', :'code'),
  'ALREADY_MEMBER', 'proprietarul nu se retrogradează acceptând o invitație de dispecer');

-- ---------- firma: câmpurile de platformă ----------
:as_system
update public.companies set status = 'SUSPENDED' where slug = 'firma-a';
:as_admin_a
select t.raises($$update public.companies set status = 'ACTIVE' where slug = 'firma-a'$$,
  'FIELD_NOT_EDITABLE', 'firma suspendată nu se reactivează singură');
select t.raises($$update public.companies set slug = 'alt-nume' where slug = 'firma-a'$$,
  'FIELD_NOT_EDITABLE', 'firma nu își schimbă adresa de pe platformă');
update public.companies set name = 'Firma A SRL' where slug = 'firma-a';
select t.ok((select name from public.companies where slug = 'firma-a') = 'Firma A SRL', 'numele firmei se poate schimba');
:as_superadmin
update public.companies set status = 'ACTIVE' where slug = 'firma-a';
select t.ok((select status from public.companies where slug = 'firma-a') = 'ACTIVE', 'Super Admin reactivează firma');

-- ---------- șoferi: contul și acordul doar prin funcții ----------
:as_admin_a
select t.raises($$update public.drivers set user_id = '00000000-0000-0000-0000-00000000b001' where full_name = 'Florin'$$,
  'permission denied', 'contul nu se leagă de șofer fără invitație');
select t.raises($$update public.drivers set public_profile = true, public_consent_at = now() where full_name = 'Florin'$$,
  'permission denied', 'acordul șoferului nu se bifează direct în tabel');
select t.raises($$insert into public.drivers (company_id, full_name, user_id)
                  values ('00000000-0000-0000-0000-0000000000a0', 'Nou', '00000000-0000-0000-0000-00000000b001')$$,
  'permission denied', 'un șofer nou nu se creează direct cu un cont legat');
insert into public.drivers (company_id, full_name, phone) values ('00000000-0000-0000-0000-0000000000a0', 'Vasile', '+40700000555');
update public.drivers set phone = '+40700000556', active = false where full_name = 'Vasile';
select t.ok((select phone from public.drivers where full_name = 'Vasile') = '+40700000556', 'numele, telefonul și starea rămân editabile');

-- ---------- accesul șoferului cere apartenența la firmă ----------
:as_driver_a
select t.ok((select count(*) from public.trips) = 1, 'șoferul cu invitație vede cursa lui');
:as_system
delete from public.company_members where user_id = '00000000-0000-0000-0000-00000000a003';
:as_driver_a
select t.ok((select count(*) from public.trips) = 0, 'fără apartenență la firmă, legătura de cont singură nu dă acces');

:as_system
insert into public.company_members (company_id, user_id, role)
values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a003', 'DRIVER');
:as_admin_a
select public.remove_member('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a003');
:as_system
select t.ok((select user_id from public.drivers where full_name = 'Ionuț') is null,
            'scoaterea șoferului din firmă îi dezleagă și contul');

-- ---------- Firma B nu atinge membrii Firmei A ----------
:as_owner_b
select t.raises($$select public.change_member_role('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e001', 'DISPATCHER')$$,
  'FORBIDDEN', 'Firma B nu schimbă roluri în Firma A');
select t.raises($$select public.remove_member('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e001')$$,
  'FORBIDDEN', 'Firma B nu scoate membri din Firma A');

rollback;
