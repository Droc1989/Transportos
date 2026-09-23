:as_anon
select t.raises('select public.consume_address_budget()', 'permission denied', 'anon nu consumă bugetul direct');
:as_owner_a
select t.raises('select public.consume_address_budget()', 'permission denied', 'firma nu consumă bugetul direct');
select t.raises('select * from private_geocoding.budget', 'permission denied', 'firma nu citește contorul');
:as_superadmin
select t.raises('select public.consume_address_budget()', 'permission denied', 'Super Admin nu este serverul');
:as_system
update private_geocoding.budget set hits = '{}';
set local role service_role;
select t.ok(bool_and(public.consume_address_budget()), 'primele 40 de apeluri sunt acceptate') from generate_series(1,40);
select t.ok(not public.consume_address_budget(), 'apelul 41 este refuzat');
reset role;
set local role service_role;
select t.ok(not public.consume_address_budget(), 'un alt client server folosește același contor');
:as_system
update private_geocoding.budget set hits = array[clock_timestamp() - interval '61 seconds'];
set local role service_role;
select t.ok(public.consume_address_budget(), 'fereastra expirată eliberează bugetul');
:as_system
select t.ok((select cardinality(hits) from private_geocoding.budget) = 1, 'istoricul expirat este eliminat');
rollback;
