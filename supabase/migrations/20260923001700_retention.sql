-- 1700 — Retenția datelor (ADR-0003, GDPR: păstrăm doar cât e necesar)
--
-- run_retention() rulează zilnic (pg_cron sau worker cu service_role):
--   * pozițiile GPS mai vechi de 90 de zile sunt rărite la o poziție pe minut pe vehicul;
--   * pozițiile mai vechi de 24 de luni sunt șterse;
--   * notificările trimise, eșuate sau anulate mai vechi de 90 de zile sunt șterse;
--   * linkurile de urmărire expirate sunt șterse;
--   * se creează partițiile GPS pentru lunile următoare.

create or replace function public.run_retention(
  p_detailed_days      int default 90,
  p_positions_months   int default 24,
  p_notification_days  int default 90
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_thinned   int;
  v_deleted   int;
  v_notif     int;
  v_tokens    int;
begin
  perform public.ensure_position_partitions(2);

  with ranked as (
    select id, recorded_at,
           row_number() over (partition by vehicle_id, date_trunc('minute', recorded_at)
                              order by recorded_at) as rn
    from public.vehicle_positions
    where recorded_at < now() - make_interval(days => p_detailed_days)
  )
  delete from public.vehicle_positions p
  using ranked r
  where p.id = r.id and p.recorded_at = r.recorded_at and r.rn > 1;
  get diagnostics v_thinned = row_count;

  delete from public.vehicle_positions
  where recorded_at < now() - make_interval(months => p_positions_months);
  get diagnostics v_deleted = row_count;

  delete from public.notification_outbox
  where status in ('SENT', 'FAILED', 'CANCELLED')
    and created_at < now() - make_interval(days => p_notification_days);
  get diagnostics v_notif = row_count;

  delete from public.booking_tracking_tokens where expires_at < now();
  get diagnostics v_tokens = row_count;

  return jsonb_build_object(
    'positions_thinned', v_thinned,
    'positions_deleted', v_deleted,
    'notifications_deleted', v_notif,
    'tracking_tokens_deleted', v_tokens
  );
end;
$$;

revoke execute on function public.run_retention(int, int, int) from public, anon, authenticated;
grant execute on function public.run_retention(int, int, int) to service_role;

-- În Supabase, cu pg_cron:
-- select cron.schedule('retention', '15 3 * * *', $$select public.run_retention()$$);
