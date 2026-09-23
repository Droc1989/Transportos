-- Firme noi și invitații pentru personal

:as_system
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000d001', 'patron-nou@test'),
  ('00000000-0000-0000-0000-00000000d002', 'dispecer-nou@test');

-- Doar Super Admin creează firme
:as_owner_a
select t.raises($$select public.create_company('Firma X', 'firma-x', 'RO')$$, 'FORBIDDEN', 'o firmă nu creează alte firme');
select t.raises($$select * from public.admin_list_companies()$$, 'FORBIDDEN', 'o firmă nu vede lista tuturor firmelor');

:as_superadmin
select public.create_company('Transport Nou SRL', 'Transport-Nou', 'at') as cid \gset
select t.ok((select slug || '/' || country from public.companies where id = :'cid') = 'transport-nou/AT',
            'slug și țara sunt normalizate');
select t.ok((select default_locale from public.company_settings where company_id = :'cid') = 'de',
            'firmă din Austria: limba implicită germană');
select t.ok((select plan_id || '/' || status from public.company_subscriptions where company_id = :'cid') = 'PILOT/TRIAL',
            'pornește pe planul Pilot');
select t.ok((select count(*) from public.admin_list_companies()) = 3, 'Super Admin vede toate firmele');

-- Invitația proprietarului
select public.create_staff_invite(:'cid', 'OWNER') as owner_code \gset
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000d001';
select public.accept_invite(:'owner_code') as res \gset
select t.ok((:'res'::jsonb ->> 'role') = 'OWNER' and (:'res'::jsonb ->> 'company') = 'Transport Nou SRL',
            'patronul intră în firmă ca proprietar');
select t.ok(public.is_company_admin(:'cid'), 'și e admin al firmei');
select t.raises(format('select public.accept_invite(%L)', :'owner_code'), 'INVITE_INVALID', 'codul nu merge de două ori');

-- Proprietarul invită un dispecer
select public.create_staff_invite(:'cid', 'DISPATCHER') as disp_code \gset
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000d002';
select t.ok((public.accept_invite(:'disp_code') ->> 'role') = 'DISPATCHER', 'dispecerul intră în firmă');
select t.ok(public.is_company_staff(:'cid') and not public.is_company_admin(:'cid'), 'dispecerul nu e admin');
select t.raises(format('select public.create_staff_invite(%L, ''ADMIN'')', :'cid'),
  'FORBIDDEN', 'dispecerul nu invită personal');

-- Un admin (nu proprietar) nu poate invita proprietari
:as_superadmin
select public.create_staff_invite('00000000-0000-0000-0000-0000000000a0', 'ADMIN') as admin_code \gset
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000d002';
select public.accept_invite(:'admin_code');
select t.raises($$select public.create_staff_invite('00000000-0000-0000-0000-0000000000a0', 'OWNER')$$,
  'FORBIDDEN', 'un admin nu poate invita un proprietar');
select t.ok(public.create_staff_invite('00000000-0000-0000-0000-0000000000a0', 'DISPATCHER') ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}$',
            'adminul poate invita dispeceri');

-- accept_invite merge și cu codurile de șofer
:as_owner_a
insert into public.drivers (id, company_id, full_name) values
  ('00000000-0000-0000-0000-0000000002a8', '00000000-0000-0000-0000-0000000000a0', 'Vasile');
select public.create_driver_invite('00000000-0000-0000-0000-0000000002a8') as drv_code \gset
:as_system
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000d003', 'vasile@test');
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000d003';
select t.ok((public.accept_invite(:'drv_code') ->> 'role') = 'DRIVER', 'același câmp acceptă și codul de șofer');
select t.raises($$select public.accept_invite('ZZZZ-ZZZZ')$$, 'INVITE_INVALID', 'cod greșit');

rollback;
