-- Codurile poștale: import legat de localități și căutare după cod.

:as_system
\set as_service 'set local role service_role; set local "request.jwt.claim.sub" = '''';'

:as_service
select public.import_places('[
  {"source_id":"gp1","name":"Bulgăruș","admin_name":"Timiș","country":"RO","kind":"village","population":900,"lat":45.914,"lng":21.073},
  {"source_id":"gp2","name":"Satu Nou","admin_name":"Timiș","country":"RO","kind":"village","population":800,"lat":45.53,"lng":21.66},
  {"source_id":"gp3","name":"Gräfelfing","admin_name":"Bayern","country":"DE","kind":"town","population":13000,"lat":48.119,"lng":11.43},
  {"source_id":"gp4","name":"Szentes","admin_name":"Csongrád-Csanád","country":"HU","kind":"town","population":27000,"lat":46.65,"lng":20.26}
]'::jsonb);

-- ---------- importul: doar cu cheia de sistem ----------
:as_disp_a
select t.raises($$select public.import_postcodes('[]'::jsonb)$$, 'permission denied', 'personalul nu importă coduri poștale');
:as_anon
select t.raises($$insert into public.place_postcodes (country, postcode, place_id) select 'RO', '300000', id from public.places limit 1$$,
  'permission denied', 'vizitatorii nu scriu coduri poștale');

:as_service
select public.import_postcodes('[
  {"country":"RO","postcode":"307241","name":"Bulgăruș","lat":45.915,"lng":21.074},
  {"country":"RO","postcode":"300001","name":"Timișoara","lat":45.754,"lng":21.226},
  {"country":"RO","postcode":"307099","name":"Bulgăruș","lat":45.914,"lng":21.073},
  {"country":"RO","postcode":"307099","name":"Satu Nou","lat":45.53,"lng":21.66},
  {"country":"DE","postcode":"80331","name":"München","lat":48.137,"lng":11.575},
  {"country":"DE","postcode":"80333","name":"München","lat":48.145,"lng":11.57},
  {"country":"DE","postcode":"80335","name":"München Maxvorstadt","lat":48.147,"lng":11.56},
  {"country":"DE","postcode":"82166","name":"Gräfelfing","lat":48.119,"lng":11.43},
  {"country":"DE","postcode":"99999","name":"Nirgendwo","lat":54.5,"lng":8.1},
  {"country":"AT","postcode":"1010","name":"Wien","lat":48.21,"lng":16.37},
  {"country":"HU","postcode":"6600","name":"Szentes","lat":46.65,"lng":20.26},
  {"country":"DE","postcode":"ABC","name":"Fals","lat":48.1,"lng":11.5}
]'::jsonb) as res \gset
select t.ok((:'res'::jsonb ->> 'linked')::int = 10 and (:'res'::jsonb ->> 'skipped')::int = 2,
            'se leagă 10 coduri; se sar codul fără localitate în apropiere și codul invalid');
:as_system
select t.ok((select count(*) from public.place_postcodes pc join public.places p on p.id = pc.place_id
             where pc.postcode = '80335' and p.name = 'München') = 1,
            'codul cu alt nume („München Maxvorstadt”) se leagă de localitatea cea mai apropiată');
:as_service
select t.ok((public.import_postcodes('[{"country":"DE","postcode":"80331","name":"München","lat":48.137,"lng":11.575}]'::jsonb) ->> 'new')::int = 0,
            'reimportul nu dublează codurile');

-- ---------- căutarea după cod (ca vizitator) ----------
:as_anon
select t.ok((select name || '|' || match || '|' || postcode from public.search_places('80331') limit 1) = 'München|postcode|80331',
            '„80331” → München');
select t.ok((select count(*) from public.search_places('8033')) = 1
            and (select match from public.search_places('8033') limit 1) = 'postcode_prefix',
            '„8033” (început de cod) → München o singură dată');
select t.ok((select name from public.search_places('D-80331') limit 1) = 'München', '„D-80331” (cu prefix de țară) → München');
select t.ok((select name from public.search_places('80331 München') limit 1) = 'München', '„80331 München” → München');
select t.ok((select count(*) from public.search_places('80331 Berlin')) = 0, 'cod și nume care nu se potrivesc: nimic');
select t.ok((select name || '|' || postcode from public.search_places('307241') limit 1) = 'Bulgăruș|307241', '„307241” → Bulgăruș');
select t.ok((select name from public.search_places('1010') limit 1) = 'Wien', '„1010” → Wien');
select t.ok((select name from public.search_places('6600') limit 1) = 'Szentes', '„6600” → Szentes');
select t.ok((select count(*) from public.search_places('307099')) = 2, 'un cod pentru două sate: apar ambele');
select t.ok((select count(*) from public.search_places('8033', 'AT')) = 0, 'filtrul pe țară și la coduri');
select t.ok((select count(*) from public.search_places('30')) = 0, 'două cifre nu sunt un cod: nicio căutare');
select t.ok((select postcode from public.search_places('Bulgăruș') limit 1) is null, 'căutarea după nume merge ca înainte');
select t.ok((select count(*) from public.place_postcodes) >= 10, 'vizitatorul poate citi codurile poștale');

rollback;
