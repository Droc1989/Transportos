-- Date demo pentru dezvoltare locală (supabase db reset).
-- Utilizatorii se creează din Studio (Authentication), apoi îi legi de firmă:
--   insert into public.company_members (company_id, user_id, role)
--   values ('11111111-1111-1111-1111-111111111111', '<id utilizator>', 'OWNER');
--   insert into public.platform_admins (user_id) values ('<id-ul tău>');

insert into public.companies (id, name, slug, country, status) values
  ('11111111-1111-1111-1111-111111111111', 'Firma Demo Transport', 'firma-demo', 'RO', 'ACTIVE');
insert into public.company_settings (company_id, show_on_public_map) values
  ('11111111-1111-1111-1111-111111111111', true);
insert into public.company_subscriptions (company_id, plan_id, status) values
  ('11111111-1111-1111-1111-111111111111', 'PILOT', 'TRIAL');

insert into public.vehicles (id, company_id, label, plate, seats) values
  ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111111', 'TM-01', 'TM01DEM', 8),
  ('22222222-2222-2222-2222-222222222202', '11111111-1111-1111-1111-111111111111', 'TM-02', 'TM02DEM', 8);
insert into public.vehicles (id, company_id, label, plate, seats, status, is_standby) values
  ('22222222-2222-2222-2222-222222222205', '11111111-1111-1111-1111-111111111111', 'TM-05', 'TM05DEM', 8, 'STANDBY', true);

insert into public.drivers (id, company_id, full_name, phone) values
  ('33333333-3333-3333-3333-333333333301', '11111111-1111-1111-1111-111111111111', 'Ionuț', '+40700000101'),
  ('33333333-3333-3333-3333-333333333302', '11111111-1111-1111-1111-111111111111', 'Florin', '+40700000102');

insert into public.customers (id, company_id, full_name, phone, locale) values
  ('44444444-4444-4444-4444-444444444401', '11111111-1111-1111-1111-111111111111', 'Ana Demo', '+40700000201', 'ro'),
  ('44444444-4444-4444-4444-444444444402', '11111111-1111-1111-1111-111111111111', 'Markus Demo', '+49150000202', 'de');

insert into public.trips (id, company_id, vehicle_id, driver_id, title, departure_at) values
  ('55555555-5555-5555-5555-555555555501', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333301',
   'Timișoara – München', date_trunc('day', now()) + interval '1 day 18 hours'),
  ('55555555-5555-5555-5555-555555555502', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222202', '33333333-3333-3333-3333-333333333302',
   'Timișoara – München', date_trunc('day', now()) + interval '1 day 20 hours');

insert into public.trip_route_points (trip_id, company_id, seq, name, location)
select trip_id, '11111111-1111-1111-1111-111111111111', seq, name,
       extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography
from (values
  (0, 'Timișoara', 45.7489, 21.2087), (1, 'Arad', 46.1866, 21.3123),
  (2, 'Budapest', 47.4979, 19.0402),  (3, 'Győr', 47.6875, 17.6504),
  (4, 'Wien', 48.2082, 16.3738),      (5, 'Linz', 48.3069, 14.2858),
  (6, 'Salzburg', 47.8095, 13.0550),  (7, 'München', 48.1351, 11.5820)
) as p(seq, name, lat, lng)
cross join (values ('55555555-5555-5555-5555-555555555501'::uuid),
                   ('55555555-5555-5555-5555-555555555502'::uuid)) as tr(trip_id);

-- Rută salvată, ca pagina „Cursă nouă” să funcționeze din prima
insert into public.route_templates (id, company_id, name) values
  ('66666666-6666-6666-6666-666666666601', '11111111-1111-1111-1111-111111111111', 'Timișoara – München prin Wien');
insert into public.route_template_points (template_id, company_id, seq, place_id)
select '66666666-6666-6666-6666-666666666601', '11111111-1111-1111-1111-111111111111', ord - 1, p.id
from unnest(array['Timișoara', 'Arad', 'Budapest', 'Győr', 'Wien', 'Linz', 'Salzburg', 'München'])
     with ordinality as u(name, ord)
join public.places p on p.name = u.name;

-- Site-ul demo al firmei: /f/firma-demo
insert into public.company_sites (company_id, published, tagline, about, phone, whatsapp, accent_color)
values ('11111111-1111-1111-1111-111111111111', true, 'Timișoara – München, de la ușă la ușă',
        E'Firmă demo pentru dezvoltare.\n\n## Ce oferim\n\n- Plecări marți și vineri\n- **Preluare de la adresă**',
        '+40 256 000 000', '+40 700 000 000', '#0B4EA2');
update public.route_templates set show_on_site = true, public_note = 'marți și vineri', price_from_cents = 9000
where id = '66666666-6666-6666-6666-666666666601';
update public.vehicles set show_on_site = true, public_description = 'Microbuz 8+1 cu aer condiționat', amenities = '{AC,USB}'
where id = '22222222-2222-2222-2222-222222222201';
insert into public.site_posts (company_id, slug, title, excerpt, body, published_at)
values ('11111111-1111-1111-1111-111111111111', 'bun-venit', 'Bun venit pe noul nostru site',
        'Acum ne găsiți și online.', 'Rezervați direct din formularul de pe site.', now());
