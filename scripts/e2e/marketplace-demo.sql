-- Date pentru marketplace_e2e.py (după fixtures.sql și site-demo.sql).
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000cc01', 'client-e2e@test')
on conflict (id) do nothing;
insert into route_templates (id, company_id, name) values
  ('00000000-0000-0000-0000-0000000006a2', '00000000-0000-0000-0000-0000000000a0', 'Timișoara – Wien')
on conflict do nothing;
insert into route_template_prices (template_id, company_id, from_seq, to_seq, price_cents) values
  ('00000000-0000-0000-0000-0000000006a2', '00000000-0000-0000-0000-0000000000a0', 0, 1, 7000)
on conflict do nothing;
update trips set template_id = '00000000-0000-0000-0000-0000000006a2' where id = '00000000-0000-0000-0000-0000000004a2';
insert into vehicle_photos (company_id, vehicle_id, kind, url) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000001a1', 'EXTERIOR', 'https://example.test/tm01-ext.jpg');
