-- Company Admin: rute-șablon și curse create din șabloane

:as_disp_a
select t.ok((select count(*) from public.places) >= 30, 'localitățile de pe coridor sunt disponibile');

select public.save_route_template(
  '00000000-0000-0000-0000-0000000000a0',
  'Timișoara – München prin Wien',
  array(select id from public.places
        where name in ('Timișoara', 'Arad', 'Budapest', 'Wien', 'Linz', 'München')
        order by array_position(array['Timișoara', 'Arad', 'Budapest', 'Wien', 'Linz', 'München'], name))
) as tpl \gset

select t.ok((select count(*) from public.route_template_points where template_id = :'tpl') = 6,
            'șablonul are 6 puncte');
select t.raises(
  $$select public.save_route_template('00000000-0000-0000-0000-0000000000a0', 'Prea scurtă',
           array(select id from public.places where name = 'Arad'))$$,
  'INVALID_ROUTE', 'o rută cu un singur punct e refuzată');

-- Cursă din șablon
select public.create_trip_from_template(:'tpl', '00000000-0000-0000-0000-0000000001a1',
       '00000000-0000-0000-0000-0000000002a1', now() + interval '3 days') as trip \gset
select t.ok((select title from public.trips where id = :'trip') = 'Timișoara – München',
            'titlul implicit: primul și ultimul oraș');
select t.ok((select count(*) from public.trip_route_points where trip_id = :'trip') = 6,
            'punctele sunt copiate în cursă');
select t.ok((select name from public.trip_route_points where trip_id = :'trip' and seq = 3) = 'Wien',
            'ordinea punctelor e păstrată');
select t.ok((select route_line is not null from public.trips where id = :'trip'),
            'traseul cursei e construit automat');

-- Cursa nouă se poate rezerva imediat pe segmente
select t.ok(public.free_seats(:'trip', 1, 5) = 8, 'cursa nouă are toate locurile libere');

-- Firma B nu vede și nu folosește șablonul Firmei A
:as_owner_b
select t.ok((select count(*) from public.route_templates) = 0, 'Firma B nu vede șabloanele Firmei A');
select t.raises(
  format('select public.create_trip_from_template(%L, %L, null, now())',
         :'tpl', '00000000-0000-0000-0000-0000000001b1'),
  'TEMPLATE_NOT_FOUND', 'Firma B nu poate crea curse din șablonul Firmei A');

-- Șoferul nu vede șabloanele
:as_driver_a
select t.ok((select count(*) from public.route_templates) = 0, 'șoferul nu vede șabloanele');

-- Doar Super Admin modifică lista de localități
:as_disp_a
select t.raises(
  $$insert into public.places (name, country, location)
    values ('Test', 'RO', st_setsrid(st_makepoint(21, 45), 4326)::geography)$$,
  'row-level security', 'firmele nu modifică lista de localități');

-- În mod doar citire nu se creează curse noi
:as_superadmin
update public.company_subscriptions set status = 'READ_ONLY'
where company_id = '00000000-0000-0000-0000-0000000000a0';
:as_disp_a
select t.raises(
  format('select public.create_trip_from_template(%L, %L, null, now() + interval ''4 days'')',
         :'tpl', '00000000-0000-0000-0000-0000000001a1'),
  'row-level security', 'în mod doar citire nu se creează curse');

rollback;
