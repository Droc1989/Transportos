-- 2000 — Drepturi explicite pentru workerul de sistem (service_role)
-- Găsit de testul cap-coadă prin API: refresh_public_live_trips (0900) nu era executabilă
-- de service_role după revoke-ul general. Nu ne bazăm pe drepturile implicite ale proiectului.

grant execute on function public.refresh_public_live_trips(interval, double precision) to service_role;
grant execute on function public.ensure_position_partitions(int) to service_role;

-- _is_platform_table (0800) rămăsese executabilă pentru toată lumea; o păstrăm doar pentru
-- utilizatorii autentificați, unde o folosește politica de audit.
revoke execute on function public._is_platform_table(text) from public, anon;
grant execute on function public._is_platform_table(text) to authenticated;
