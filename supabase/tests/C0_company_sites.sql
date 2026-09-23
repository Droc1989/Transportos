-- Site-urile firmelor

-- Nepublicat: vizitatorul nu vede nimic
:as_anon
select t.ok(public.get_company_site('firma-a') is null, 'site nepublicat: nimic');
select t.raises($$select count(*) from public.company_sites$$, 'permission denied', 'anonimul nu citește tabelele site-ului');

-- Doar adminul configurează site-ul; dispecerul scrie știri
:as_disp_a
select t.raises($$insert into public.company_sites (company_id, published) values ('00000000-0000-0000-0000-0000000000a0', true)$$,
  'row-level security', 'dispecerul nu publică site-ul');
insert into public.site_posts (company_id, slug, title, excerpt, body, published_at) values
  ('00000000-0000-0000-0000-0000000000a0', 'curse-noi-spre-viena', 'Curse noi spre Viena', 'Din octombrie, de două ori pe săptămână.',
   'Plecăm marți și vineri.', now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000a0', 'ciorna', 'O ciornă', null, 'Încă nu.', null),
  ('00000000-0000-0000-0000-0000000000a0', 'programata', 'Programată', null, 'Mâine.', now() + interval '1 day');

:as_owner_a
insert into public.company_sites (company_id, published, tagline, about, phone, whatsapp, accent_color)
values ('00000000-0000-0000-0000-0000000000a0', true, 'Timișoara – München de 12 ani', 'Suntem o firmă de familie.',
        '+40 256 000 000', '+40700000000', '#C0392B');
update public.route_templates set show_on_site = true where company_id = '00000000-0000-0000-0000-0000000000a0';
update public.vehicles set show_on_site = true, public_description = 'Microbuz cu aer condiționat',
       amenities = '{AC,USB}' where label = 'TM-01';

-- Profilul public al șoferului cere acord
select t.raises($$select public.set_driver_public_profile('00000000-0000-0000-0000-0000000002a1', true, false, 'Bio')$$,
  'INVALID_REQUEST', 'fără acordul șoferului, profilul nu devine public');
select public.set_driver_public_profile('00000000-0000-0000-0000-0000000002a1', true, true,
  'Conduc pe ruta asta din 2015.', '{ro,de}', 2010);
update public.drivers set full_name = 'Florin Pop' where id = '00000000-0000-0000-0000-0000000002a2';
select t.ok((select public_consent_at is not null from public.drivers where id = '00000000-0000-0000-0000-0000000002a1'),
            'acordul e înregistrat, cu data');
:as_owner_a
select t.raises($$update public.drivers set public_profile = true where id = '00000000-0000-0000-0000-0000000002a2'$$,
  'drivers_public_needs_consent', 'nici direct în tabel nu se poate publica fără acord');

-- Vizitatorul vede site-ul publicat
:as_anon
select public.get_company_site('firma-a') as site \gset
select t.ok((:'site'::jsonb ->> 'name') = 'Firma A' and (:'site'::jsonb ->> 'accent_color') = '#C0392B', 'numele și culoarea firmei');
select t.ok(jsonb_array_length(:'site'::jsonb -> 'fleet') = 1, 'doar vehiculele alese apar în flotă');
select t.ok(jsonb_array_length(:'site'::jsonb -> 'drivers') = 1
            and (:'site'::jsonb -> 'drivers' -> 0 ->> 'name') = 'Ionuț', 'doar șoferii cu acord apar');
select t.ok(jsonb_array_length(:'site'::jsonb -> 'posts') = 1, 'doar știrile publicate, nu ciornele sau cele programate');
select t.ok(not (:'site'::jsonb::text ~ '(TM01AAA|\+40700000001|plate)'), 'fără numere de înmatriculare sau date de clienți');
select t.ok((public.get_site_post('firma-a', 'curse-noi-spre-viena') ->> 'body') = 'Plecăm marți și vineri.', 'articolul complet');
select t.ok(public.get_site_post('firma-a', 'ciorna') is null, 'ciorna nu e publică');
select t.ok(public.get_site_post('firma-a', 'programata') is null, 'articolul programat nu apare înainte de dată');

-- Numele șoferului: prenume + inițială
:as_owner_a
select public.set_driver_public_profile('00000000-0000-0000-0000-0000000002a2', true, true, null);
:as_anon
select t.ok(exists (select 1 from jsonb_array_elements(public.get_company_site('firma-a') -> 'drivers') d
                    where d ->> 'name' = 'Florin P.'), 'numele complet nu apare: „Florin P.”');

-- Cereri de rezervare de pe site
select t.ok(public.submit_booking_request('firma-a', 'Maria Ionescu', '+40 722 111 222', 'Lugoj', 'Linz',
            current_date + 5, 2, 'Avem și un cărucior.'), 'vizitatorul trimite o cerere');
select t.raises($$select public.submit_booking_request('firma-a', 'X', '1', 'A', 'B', null, 1)$$,
  'INVALID_REQUEST', 'cererea incompletă e refuzată');
select t.raises($$select public.submit_booking_request('firma-b', 'Maria', '+40722111222', 'Arad', 'Wien', null, 1)$$,
  'SITE_NOT_FOUND', 'site nepublicat: nu primește cereri');
select public.submit_booking_request('firma-a', 'Maria Ionescu', '+40722111222', 'Lugoj', 'Linz', null, 1)
from generate_series(1, 4);
select t.raises($$select public.submit_booking_request('firma-a', 'Maria Ionescu', '+40722111222', 'Lugoj', 'Linz', null, 1)$$,
  'REQUEST_LIMIT', 'a șasea cerere în aceeași oră e refuzată');

:as_disp_a
select t.ok(public.count_new_booking_requests('00000000-0000-0000-0000-0000000000a0') = 5, 'dispecerul vede cererile noi');
select t.ok((select phone from public.booking_requests limit 1) = '+40722111222', 'telefonul e curățat de spații');
update public.booking_requests set status = 'CONVERTED', handled_at = now() where message is not null;
select t.ok(public.count_new_booking_requests('00000000-0000-0000-0000-0000000000a0') = 4, 'cererea preluată nu mai e nouă');
:as_owner_b
select t.ok((select count(*) from public.booking_requests) = 0, 'Firma B nu vede cererile Firmei A');

-- Domeniul propriu
:as_owner_a
update public.company_sites set custom_domain = 'transport-a.ro' where company_id = '00000000-0000-0000-0000-0000000000a0';
:as_anon
select t.ok(public.resolve_site_domain('www.transport-a.ro:443') = 'firma-a', 'domeniul propriu duce la site-ul firmei');
select t.ok(public.resolve_site_domain('altceva.ro') is null, 'domeniu necunoscut: nimic');

-- Fără funcția din plan sau cu firma suspendată, site-ul dispare
:as_system
insert into public.company_feature_overrides (company_id, feature_key, enabled)
values ('00000000-0000-0000-0000-0000000000a0', 'company_website', false);
:as_anon
select t.ok(public.get_company_site('firma-a') is null and public.resolve_site_domain('transport-a.ro') is null,
            'fără funcția din plan: site oprit');
:as_system
delete from public.company_feature_overrides where feature_key = 'company_website';
update public.companies set status = 'SUSPENDED' where slug = 'firma-a';
:as_anon
select t.ok(public.get_company_site('firma-a') is null, 'firmă suspendată: site oprit');

rollback;
