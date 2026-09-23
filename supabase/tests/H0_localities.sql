-- Localitățile (sate, comune, orașe) din RO, AT, DE, HU: import, căutare, sate cu același nume.

:as_system
select id as timisoara_id from public.places where name = 'Timișoara' and source = 'core' \gset
\set as_service 'set local role service_role; set local "request.jwt.claim.sub" = '''';'

-- ---------- importul: doar cu cheia de sistem ----------
:as_disp_a
select t.raises($$select public.import_places('[]'::jsonb)$$, 'permission denied', 'personalul firmelor nu importă localități');
:as_anon
select t.raises($$select public.import_places('[]'::jsonb)$$, 'permission denied', 'vizitatorii nu importă localități');
select t.raises($$insert into public.places (name, country, location) values ('X', 'RO', 'POINT(21 45)')$$,
  'permission denied', 'vizitatorii nu scriu în lista de localități');

:as_service
select public.import_places('[
  {"source_id":"gn1","name":"Satu Nou","admin_name":"Arad","country":"RO","kind":"village","population":450,"lat":46.37,"lng":21.83},
  {"source_id":"gn2","name":"Satu Nou","admin_name":"Timiș","country":"RO","kind":"village","population":800,"lat":45.53,"lng":21.66},
  {"source_id":"gn3","name":"Satu Nou","admin_name":"Brașov","country":"RO","kind":"village","population":3000,"lat":45.85,"lng":25.95},
  {"source_id":"gn4","name":"Bulgăruș","admin_name":"Timiș","country":"RO","kind":"village","population":900,"lat":45.914,"lng":21.073},
  {"source_id":"gn5","name":"Arad","admin_name":"Arad","country":"RO","kind":"city","population":159000,"lat":46.18,"lng":21.31},
  {"source_id":"gn6","name":"Neudorf","admin_name":"Niederösterreich","country":"AT","kind":"village","population":500,"lat":48.3,"lng":16.1},
  {"source_id":"gn7","name":"Neudorf","admin_name":"Steiermark","country":"AT","kind":"village","population":300,"lat":47.1,"lng":15.4},
  {"source_id":"gn8","name":"Schöneberg","admin_name":"Berlin","country":"DE","kind":"locality","population":120000,"lat":52.48,"lng":13.35},
  {"source_id":"gn9","name":"Szentes","admin_name":"Csongrád-Csanád","country":"HU","kind":"town","population":27000,"lat":46.65,"lng":20.26},
  {"source_id":"gn10","name":"Paris","admin_name":"Île-de-France","country":"FR","kind":"city","population":2000000,"lat":48.85,"lng":2.35},
  {"source_id":"gn11","name":"Fals","admin_name":"Timiș","country":"RO","kind":"planeta","population":1,"lat":45.5,"lng":21.5}
]'::jsonb) as imported \gset
select t.ok(:imported = 8, 'se importă 8 localități: fără dublura Aradului, fără țări sau tipuri nepermise');

:as_system
select t.ok((select count(*) from public.places where name = 'Arad' and country = 'RO') = 1,
            'orașul Arad existent nu e dublat de import');
select t.ok((select id from public.places where name = 'Timișoara' and source = 'core') = :'timisoara_id',
            'orașele de pe coridor își păstrează identificatorul (rutele firmelor rămân valabile)');

-- ---------- căutarea (ca vizitator) ----------
:as_anon
select t.ok((select count(*) from public.search_places('satu nou') where match = 'exact') = 3,
            'toate cele trei sate „Satu Nou” apar');
select t.ok((select string_agg(admin_name, ',') from (select admin_name from public.search_places('Satu Nou') limit 3) x) = 'Brașov,Timiș,Arad',
            'satele cu același nume se deosebesc prin județ, cele mai mari primele');
select t.ok((select name from public.search_places('Bulgarus') limit 1) = 'Bulgăruș', 'fără diacritice: „Bulgarus” → Bulgăruș');
select t.ok((select name || '|' || match from public.search_places('Viena') limit 1) = 'Wien|alias', 'denumirea uzuală: „Viena” → Wien');
select t.ok((select name || '|' || match from public.search_places('Vien') limit 1) = 'Wien|prefix',
            'începutul denumirii uzuale: „Vien” (de la Viena) → Wien');
select t.ok((select name from public.search_places('Munic') limit 1) = 'München', '„Munic” (de la Munich) → München');
select t.ok((select name from public.search_places('Muenchen') limit 1) = 'München', 'transliterare germană: „Muenchen” → München');
select t.ok((select name from public.search_places('munchen') limit 1) = 'München', '„munchen” → München');
select t.ok((select name from public.search_places('Frankfurt') limit 1) = 'Frankfurt am Main', '„Frankfurt” → Frankfurt am Main');
select t.ok((select name from public.search_places('Cluj') limit 1) = 'Cluj-Napoca', '„Cluj” → Cluj-Napoca');
select t.ok((select name || '|' || match from public.search_places('Timisoar') limit 1) = 'Timișoara|prefix', 'începutul numelui: „Timisoar”');
select t.ok(exists (select 1 from public.search_places('Timisora') where name = 'Timișoara'), 'greșeală de scriere: „Timisora” găsește Timișoara');
select t.ok((select count(*) from public.search_places('Neudorf', 'AT')) = 2 and (select count(*) from public.search_places('Neudorf', 'DE')) = 0,
            'filtrul pe țară');
select t.ok((select count(*) from public.search_places('a')) = 0, 'o singură literă: nicio căutare');
select t.ok((select count(*) from public.search_places('e', null, 500)) = 0 and (select count(*) from public.search_places('ar', null, 500)) <= 20,
            'cel mult 20 de rezultate, oricât s-ar cere');
select t.ok((select count(*) from public.search_places('Paris')) = 0, 'localitățile din afara celor 4 țări nu există');
select t.ok((select count(*) from public.public_places()) = 38, 'lista scurtă de orașe rămâne cele 38 de pe coridor');
select t.ok((select count(*) from public.get_places(array(select id from public.places where name = 'Satu Nou'))) = 3,
            'localitățile alese se citesc după identificator');

-- ---------- reimportul actualizează, nu dublează ----------
:as_service
select public.import_places('[{"source_id":"gn1","name":"Satu Nou","admin_name":"Arad","country":"RO","kind":"village","population":470,"lat":46.37,"lng":21.83}]'::jsonb);
:as_system
select t.ok((select count(*) from public.places where name = 'Satu Nou') = 3
            and (select population from public.places where source_id = 'gn1') = 470, 'reimportul actualizează localitatea existentă');

-- ---------- o cursă găsită pornind dintr-un sat ----------
:as_anon
select lat as blat, lng as blng from public.search_places('Bulgăruș') limit 1 \gset
select t.ok(exists (select 1 from public.search_marketplace(:blat, :blng, 48.14, 11.58, 1, now(), now() + interval '3 days')
                    where company_name = 'Firma A'),
            'din satul Bulgăruș se găsește microbuzul care trece pe lângă el spre München');

rollback;
