-- Harta publică: doar curse în mers, cu locuri, de la firme care au ales,
-- cu poziție rotunjită și întârziată.

:as_system
update public.trips set status = 'IN_PROGRESS' where id = '00000000-0000-0000-0000-0000000004a1';

-- poziții: una acum 10 minute (vizibilă, întârziată), una acum 1 minut (încă nu)
insert into public.vehicle_positions (company_id, vehicle_id, trip_id, location, speed_kmh, recorded_at) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000004a1',
   st_setsrid(st_makepoint(19.1234, 47.4567), 4326)::geography, 92, now() - interval '10 minutes'),
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000004a1',
   st_setsrid(st_makepoint(17.9000, 47.6000), 4326)::geography, 95, now() - interval '1 minute');

-- Planul Start nu include harta publică
select t.ok(public.refresh_public_live_trips() = 0, 'fără funcția public_map, cursa nu apare');

-- Cu funcția pornită apare, rotunjit și întârziat
insert into public.company_feature_overrides (company_id, feature_key, enabled)
values ('00000000-0000-0000-0000-0000000000a0', 'public_map', true);
select t.ok(public.refresh_public_live_trips() = 1, 'cursa apare pe hartă');
select t.ok((select round(approx_lng::numeric, 4) from public.public_live_trips) = 19.1, 'longitudine rotunjită la grila de 0.05');
select t.ok((select round(approx_lat::numeric, 4) from public.public_live_trips) = 47.45, 'latitudine rotunjită la grila de 0.05');
select t.ok((select heading_to from public.public_live_trips) = 'München', 'direcția e afișată');
select t.ok((select 'Wien' = any(next_points) from public.public_live_trips), 'orașele următoare sunt afișate');
select t.ok((select free_seats from public.public_live_trips) = 8, 'locurile libere pe porțiunea rămasă');

-- Vizitatorul anonim citește harta, dar nu poate s-o regenereze sau să vadă poziții reale
:as_anon
select t.ok((select count(*) from public.public_live_trips) = 1, 'anonimul vede harta publică');
select t.raises($$select public.refresh_public_live_trips()$$, 'permission denied', 'anonimul nu regenerează harta');
select t.raises($$select count(*) from public.vehicle_positions$$, 'permission denied', 'anonimul nu vede poziții reale');

-- Firma care nu a ales harta publică nu apare
:as_system
update public.company_settings set show_on_public_map = false
where company_id = '00000000-0000-0000-0000-0000000000a0';
select t.ok(public.refresh_public_live_trips() = 0, 'fără acordul firmei, cursa nu apare');

-- Vehicul oprit (viteză sub 5 km/h) nu apare
update public.company_settings set show_on_public_map = true
where company_id = '00000000-0000-0000-0000-0000000000a0';
update public.vehicle_positions set speed_kmh = 0 where recorded_at < now() - interval '5 minutes';
select t.ok(public.refresh_public_live_trips() = 0, 'vehiculul oprit nu apare');

rollback;
