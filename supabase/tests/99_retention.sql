-- Retenția datelor
set local client_min_messages = warning;

:as_system
-- 3 poziții în același minut, acum 100 de zile; 2 poziții în același minut, azi
insert into public.vehicle_positions (company_id, vehicle_id, location, recorded_at)
select '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000001a1',
       st_setsrid(st_makepoint(21.2, 45.7), 4326)::geography, ts
from unnest(array[
  date_trunc('minute', now() - interval '100 days') + interval '5 seconds',
  date_trunc('minute', now() - interval '100 days') + interval '25 seconds',
  date_trunc('minute', now() - interval '100 days') + interval '45 seconds',
  date_trunc('minute', now() - interval '3 years'),
  now() - interval '30 seconds',
  now() - interval '20 seconds'
]) as ts;

-- o notificare trimisă acum 120 de zile și una recentă
:as_disp_a
select public.book_seats('00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000003a1',
                         1, 0, 4, p_confirm => true) as b \gset
:as_system
insert into public.notification_outbox (company_id, booking_id, template_key, channel, recipient, dedupe_key, status, created_at)
values ('00000000-0000-0000-0000-0000000000a0', :'b', 'BOOKING_CONFIRMED', 'PUSH', '+40700000001', 'veche', 'SENT',
        now() - interval '120 days');

set local role service_role;
select public.run_retention() as r \gset
reset role;

select t.ok((:'r'::jsonb ->> 'positions_thinned')::int = 2, 'pozițiile vechi sunt rărite la una pe minut');
select t.ok((:'r'::jsonb ->> 'positions_deleted')::int = 1, 'pozițiile de peste 24 de luni sunt șterse');
select t.ok((select count(*) from public.vehicle_positions where recorded_at > now() - interval '1 hour') = 2,
            'pozițiile recente rămân toate');
select t.ok((:'r'::jsonb ->> 'notifications_deleted')::int = 1, 'notificările vechi sunt șterse');
select t.ok((select count(*) from public.notification_outbox where booking_id = :'b') = 1,
            'notificarea recentă rămâne');
select t.ok(to_regclass(format('public.vehicle_positions_%s',
            to_char(now() + interval '2 months', 'YYYY_MM'))) is not null,
            'partițiile pentru lunile următoare există');

:as_disp_a
select t.raises($$select public.run_retention()$$, 'permission denied', 'doar jobul de sistem rulează retenția');

rollback;
