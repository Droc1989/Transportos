-- Drepturile de execuție pe funcții, pe rol (regresie: refresh_public_live_trips fără service_role)

-- Anonimul poate apela doar funcțiile publice: linkul de urmărire și site-urile firmelor
select t.ok(
  (select array_agg(p.proname order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
     and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype)
  = array['get_company_site', 'get_site_post', 'get_tracking', 'get_tracking_vehicle', 'resolve_site_domain', 'submit_booking_request']::name[],
  'anonimul poate apela doar funcțiile publice (urmărire, site-uri)');

-- Funcțiile workerului: executabile de service_role, nu de utilizatori
select t.ok(bool_and(has_function_privilege('service_role', f, 'execute')), 'service_role rulează toate funcțiile workerului')
from unnest(array[
  'public.refresh_public_live_trips(interval, double precision)',
  'public.enqueue_eta_notifications()',
  'public.claim_notifications(integer)',
  'public.finish_notification(bigint, boolean, text)',
  'public.update_stop_etas(uuid, uuid[], timestamp with time zone[])',
  'public.worker_tracking_link(uuid)',
  'public.run_retention(integer, integer, integer)',
  'public.ensure_position_partitions(integer)'
]) as f;

select t.ok(not bool_or(has_function_privilege('authenticated', f, 'execute')), 'utilizatorii nu rulează funcțiile workerului')
from unnest(array[
  'public.refresh_public_live_trips(interval, double precision)',
  'public.enqueue_eta_notifications()',
  'public.claim_notifications(integer)',
  'public.finish_notification(bigint, boolean, text)',
  'public.worker_tracking_link(uuid)',
  'public.run_retention(integer, integer, integer)'
]) as f;

-- Funcțiile interne (cu „_” în față) nu sunt executabile de nimeni în afară de proprietar
select t.ok(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like '\_%' and p.prokind = 'f'
    and p.proname not in ('_is_platform_table')
    and (has_function_privilege('authenticated', p.oid, 'execute')
         or has_function_privilege('anon', p.oid, 'execute'))
), 'funcțiile interne nu sunt expuse');

-- Toate funcțiile security definer au search_path fixat
select t.ok(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
), 'orice funcție security definer are search_path fixat');

rollback;
