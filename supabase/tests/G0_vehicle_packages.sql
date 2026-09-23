:as_system
insert into auth.users(id,email) values('00000000-0000-0000-0000-00000000c777','package-owner@test');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000c777',true);
select public.register_company_with_package('Pachete test','pachete-test','RO','RO111','LIC111','+40700111222',true,3,130) as cid \gset
select t.ok((select monthly_eur=130 and vehicle_limit=3 from public.company_vehicle_packages where company_id=:'cid'),'preț și limită salvate');
select t.ok((select count(*) from public.vehicle_package_catalog where
 (vehicles_from=1 and vehicles_to=3 and monthly_eur=130) or
 (vehicles_from=4 and vehicles_to=6 and monthly_eur=200) or
 (vehicles_from=7 and vehicles_to=10 and monthly_eur=300))=3,'catalog inițial');
select t.raises($$select public.admin_save_vehicle_packages('[{"vehicles_from":1,"vehicles_to":20,"monthly_eur":1}]')$$,'FORBIDDEN','firma nu modifică catalogul');
select t.raises($$update public.vehicle_package_catalog set monthly_eur=1$$,'permission denied','firma nu scrie direct catalogul');
select t.raises(format('update public.company_vehicle_packages set monthly_eur=1 where company_id=%L',:'cid'),'permission denied','firma nu schimbă prețul salvat');
select t.raises(format('select public.admin_set_company_vehicle_package(%L,3,1)',:'cid'),'FORBIDDEN','firma nu folosește RPC admin');
:as_owner_b
select t.ok((select count(*) from public.company_vehicle_packages where company_id=:'cid')=0,'altă firmă nu vede prețul');
:as_driver_a
select t.ok((select count(*) from public.company_vehicle_packages)=0,'șoferul nu vede pachetele firmelor');
:as_superadmin
select t.ok((select monthly_eur=130 from public.company_vehicle_packages where company_id=:'cid'),'admin vede prețul la aprobare');
select t.raises($$select public.admin_save_vehicle_packages('[{"vehicles_from":1,"vehicles_to":3,"monthly_eur":130},{"vehicles_from":3,"vehicles_to":6,"monthly_eur":200}]')$$,'PACKAGE_CATALOG_INVALID','suprapunerea refuzată');
select t.raises($$select public.admin_save_vehicle_packages('[{"vehicles_from":1,"vehicles_to":3,"monthly_eur":130},{"vehicles_from":5,"vehicles_to":10,"monthly_eur":300}]')$$,'PACKAGE_CATALOG_INVALID','golul refuzat');
select t.raises($$select public.admin_save_vehicle_packages('[{"vehicles_from":2,"vehicles_to":10,"monthly_eur":300}]')$$,'PACKAGE_CATALOG_INVALID','trebuie să înceapă cu 1');
select t.raises($$select public.admin_save_vehicle_packages('[]')$$,'PACKAGE_CATALOG_INVALID','catalog gol refuzat');
select t.raises($$select public.admin_save_vehicle_packages('[{"vehicles_from":1,"vehicles_to":10,"monthly_eur":-1}]')$$,'PACKAGE_CATALOG_INVALID','preț negativ refuzat');
select public.admin_save_vehicle_packages('[{"vehicles_from":1,"vehicles_to":3,"monthly_eur":150},{"vehicles_from":4,"vehicles_to":6,"monthly_eur":220},{"vehicles_from":7,"vehicles_to":12,"monthly_eur":320}]');
select t.ok((select max(vehicles_to)=12 from public.vehicle_package_catalog),'maximul este din catalog, nu fix 10');
select t.ok((select monthly_eur=130 from public.company_vehicle_packages where company_id=:'cid'),'catalogul nou nu schimbă prețul firmei');
select public.admin_set_company_vehicle_package(:'cid',3,140);
select t.ok((select monthly_eur=140 from public.company_vehicle_packages where company_id=:'cid'),'numai modificarea explicită a adminului schimbă prețul');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000c777',true);
insert into public.vehicles(id,company_id,label,plate,seats,manufacture_year)
select ('00000000-0000-0000-0000-00000000d0'||lpad(n::text,2,'0'))::uuid,:'cid','Bus '||n,'TEST'||n,8,2020 from generate_series(1,12) n;
select t.raises(format($$insert into public.vehicles(company_id,label,seats) values(%L,'Bus 13',8)$$,:'cid'),'PLAN_LIMIT_REACHED','al 13-lea depășește catalogul');
select t.raises(format('select public.submit_company_for_review(%L)',:'cid'),'REGISTRATION_INCOMPLETE','flota incompletă nu trimite');
insert into public.vehicle_photos(company_id,vehicle_id,kind,url)
select :'cid',v.id,k,'https://example.test/photo.jpg' from public.vehicles v
cross join (values('EXTERIOR'),('INTERIOR')) kinds(k) where v.company_id=:'cid' and v.label in('Bus 1','Bus 2','Bus 3');
select public.declare_vehicle_insurance(id,current_date+200,current_date+200,true)
from public.vehicles where company_id=:'cid' and label in('Bus 1','Bus 2','Bus 3');
select t.raises(format('select public.submit_company_for_review(%L)',:'cid'),'REGISTRATION_INCOMPLETE','trei complete nu înlocuiesc celelalte microbuze incomplete');
:as_superadmin
select public.review_vehicle(('00000000-0000-0000-0000-00000000d0'||lpad(n::text,2,'0'))::uuid,true) from generate_series(1,3) n;
select t.raises($$select public.review_vehicle('00000000-0000-0000-0000-00000000d004',true)$$,'PLAN_LIMIT_REACHED','pachetul 1–3 nu permite a patra aprobare');
select t.ok((select count(*) from public.vehicles where company_id=:'cid' and approval_status='APPROVED')=3,'au rămas trei aprobate');
select public.admin_set_company_vehicle_package(:'cid',4,220);
select public.review_vehicle('00000000-0000-0000-0000-00000000d004',true);
select t.raises(format('select public.admin_set_company_vehicle_package(%L,3,150)',:'cid'),'PLAN_LIMIT_REACHED','pachetul nu scade sub flota aprobată');
select t.raises($$select public.admin_save_vehicle_packages('[{"vehicles_from":1,"vehicles_to":6,"monthly_eur":200}]')$$,'PLAN_LIMIT_REACHED','maximul nu scade sub flota existentă');
select t.ok((select max(vehicles_to)=12 from public.vehicle_package_catalog),'catalogul rămâne neschimbat după refuz');
:as_system
insert into auth.users(id,email) values('00000000-0000-0000-0000-00000000c778','package-new@test');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000c778',true);
select t.raises($$select public.register_company_with_package('Firma nouă','noua','RO','RO111','LIC111','+40700111222',true,2,130)$$,'PACKAGE_PRICE_CHANGED','preț vechi în browser cere reconfirmare');
select public.register_company_with_package('Firma nouă','noua','RO','RO111','LIC111','+40700111222',true,12,320) as newcid \gset
select t.ok((select vehicle_limit=12 and monthly_eur=320 from public.company_vehicle_packages where company_id=:'newcid'),'noua firmă folosește catalogul actualizat');
rollback;
