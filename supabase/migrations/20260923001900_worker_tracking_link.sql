-- 1900 — Linkul de urmărire creat de worker (service_role) pentru mesajele către client
--
-- Workerul pune linkul în mesajele PICKUP_ETA, BOOKING_CONFIRMED și DRIVER_ARRIVED. Dacă
-- rezervarea are deja un link valid, nu îl poate refolosi (în bază e doar hash-ul), așa că
-- se creează unul nou: linkul din ultimul mesaj primit e mereu cel valid.
-- Dreptul de execuție e doar pentru service_role.

create or replace function public.worker_tracking_link(p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company   uuid;
  v_departure timestamptz;
  v_token     text;
begin
  select b.company_id, t.departure_at into v_company, v_departure
  from public.bookings b join public.trips t on t.id = b.trip_id
  where b.id = p_booking_id;
  if v_company is null or not public.has_feature(v_company, 'tracking_link') then
    return null;
  end if;

  v_token := rtrim(translate(encode(uuid_send(gen_random_uuid()) || uuid_send(gen_random_uuid()), 'base64'),
                             '+/', '-_'), '=');
  insert into public.booking_tracking_tokens (booking_id, company_id, token_hash, expires_at)
  values (p_booking_id, v_company, public._token_hash(v_token), v_departure + interval '3 days')
  on conflict (booking_id) do update
    set token_hash = excluded.token_hash, created_at = now(), expires_at = excluded.expires_at;
  return v_token;
end;
$$;

revoke execute on function public.worker_tracking_link(uuid) from public, anon, authenticated;
grant execute on function public.worker_tracking_link(uuid) to service_role;
