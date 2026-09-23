-- Conținut de probă pentru site-ul Firmei A (după fixtures.sql). Folosit de sites.e2e.mjs.
insert into company_sites (company_id, published, tagline, about, phone, whatsapp, email, address, accent_color, custom_domain)
values ('00000000-0000-0000-0000-0000000000a0', true, 'Timișoara – München de 12 ani',
 E'Suntem o firmă de familie din Timișoara.\n\n## De ce noi\n\n- Plecări de marți și vineri\n- **Preluare de la adresă**\n\nDetalii pe [pagina ARR](https://arr.ro).',
 '+40 256 000 000', '+40 700 000 000', 'contact@firma-a.test', 'Str. Exemplu 1, Timișoara', '#C0392B', 'transport-a.test');
insert into route_templates (id, company_id, name, show_on_site, public_note, price_from_cents)
values ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-0000000000a0', 'Timișoara – München prin Wien', true, 'marți și vineri', 9000);
insert into route_template_points (template_id, company_id, seq, place_id)
select '66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-0000000000a0', o - 1, p.id
from unnest(array['Timișoara','Arad','Wien','München']) with ordinality u(n, o) join places p on p.name = u.n;
update vehicles set show_on_site = true, public_description = 'Microbuz cu aer condiționat', amenities = '{AC,USB,Wi-Fi}' where label = 'TM-01';
update drivers set public_profile = true, public_bio = 'Conduc pe ruta asta din 2015.', languages = '{ro,de}',
       driving_since = 2010, public_consent_at = now() where full_name = 'Ionuț';
insert into site_posts (company_id, slug, title, excerpt, body, published_at) values
 ('00000000-0000-0000-0000-0000000000a0', 'curse-noi-spre-viena', 'Curse noi spre Viena', 'Din octombrie, de două ori pe săptămână.',
  E'Plecăm **marți și vineri** din Timișoara.\n\n<script>alert(1)</script>', now() - interval '1 day'),
 ('00000000-0000-0000-0000-0000000000a0', 'ciorna', 'O ciornă', null, 'x', null);
