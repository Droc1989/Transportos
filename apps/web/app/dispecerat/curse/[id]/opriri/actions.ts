'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import type { StopKind } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text } from '@/lib/form';
import { planOrder, routeLegs } from '@/lib/routing';
import { applyStopPlan, buildStopPlan, type PlanStop } from '@/lib/routing/stop-plan';
import { computeSchedule } from '@/lib/schedule';

function back(tripId: string, params: Record<string, string> = {}): never {
  const query = new URLSearchParams(params).toString();
  redirect(`/dispecerat/curse/${tripId}/opriri${query ? `?${query}` : ''}`);
}

export async function moveStop(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const tripId = text(form, 'trip_id');
  const { error } = await supabase.rpc('move_trip_stop', {
    p_stop_id: text(form, 'stop_id'),
    p_delta: Number(text(form, 'delta')),
  });
  revalidatePath(`/dispecerat/curse/${tripId}/opriri`);
  if (error) back(tripId, { error: await errorMessage(error) });
  back(tripId);
}

export async function autoOrder(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const tripId = text(form, 'trip_id');
  const { error } = await supabase.rpc('auto_order_trip_stops', { p_trip_id: tripId });
  revalidatePath(`/dispecerat/curse/${tripId}/opriri`);
  if (error) back(tripId, { error: await errorMessage(error) });
  back(tripId);
}

type StopRow = { id: string; kind: StopKind; lat: number | null; lng: number | null };

/** Calculează ora planificată a fiecărei opriri: plecare + drum + timp de oprire. */
type Supabase = Awaited<ReturnType<typeof requireStaffCompany>>['supabase'];

export async function computeTimes(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const tripId = text(form, 'trip_id');
  const r = await recomputeTimes(supabase, tripId);
  back(tripId, r.error ? { error: r.error } : { times: r.approximate ? 'approximate' : 'ok' });
}

/** Orele planificate ale opririlor: plecare + drum (real sau aproximativ) + timp de oprire. */
async function recomputeTimes(supabase: Supabase, tripId: string): Promise<{ approximate: boolean; error?: string }> {
  const [trip, points, stops] = await Promise.all([
    supabase.from('trips').select('departure_at').eq('id', tripId).single<{ departure_at: string }>(),
    supabase.rpc('get_trip_route_points', { p_trip_id: tripId }),
    supabase.rpc('get_trip_stops', { p_trip_id: tripId }),
  ]);
  if (trip.error || points.error || stops.error) {
    return { approximate: false, error: await errorMessage(trip.error ?? points.error ?? stops.error) };
  }

  const start = ((points.data ?? []) as { lat: number; lng: number }[])[0];
  const list = ((stops.data ?? []) as StopRow[]).filter((s) => s.lat !== null && s.lng !== null);
  if (!start || list.length === 0) return { approximate: false };

  const waypoints = [start, ...list].map((p) => ({ lat: p!.lat as number, lng: p!.lng as number }));
  const result = await routeLegs(waypoints);
  const times = computeSchedule(new Date(trip.data!.departure_at), result.legs, list.map((s) => s.kind));

  const { error } = await supabase.rpc('set_stop_planned_times', {
    p_trip_id: tripId,
    p_stop_ids: list.map((s) => s.id),
    p_times: times.map((d) => d.toISOString()),
  });
  revalidatePath(`/dispecerat/curse/${tripId}/opriri`);
  if (error) return { approximate: false, error: await errorMessage(error) };
  return { approximate: result.approximate };
}

/**
 * Optimizează ordinea opririlor din aceeași zonă (de ex. toate preluările din Timișoara și din satele
 * din jur): Route Planner pe drum real, sau metoda locală. Ordinea pe traseu nu se schimbă; baza de
 * date verifică regulile (set_trip_stop_order). Apoi recalculează orele.
 */
export async function optimizeStops(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const tripId = text(form, 'trip_id');
  const [stops, bookings, points] = await Promise.all([
    supabase.rpc('get_trip_stops', { p_trip_id: tripId }),
    supabase.from('bookings').select('id, from_seq, to_seq').eq('trip_id', tripId)
      .returns<{ id: string; from_seq: number; to_seq: number }[]>(),
    supabase.rpc('get_trip_route_points', { p_trip_id: tripId }),
  ]);
  if (stops.error || bookings.error || points.error) {
    back(tripId, { error: await errorMessage(stops.error ?? bookings.error ?? points.error) });
  }
  const zones = new Map((bookings.data ?? []).map((b) => [b.id, b]));
  const rows = (stops.data ?? []) as (StopRow & { status: string; booking_id: string })[];
  const planStops: PlanStop[] = rows.map((s) => ({
    id: s.id, kind: s.kind as PlanStop['kind'], status: s.status, lat: s.lat, lng: s.lng,
    zone: s.kind === 'PICKUP' ? zones.get(s.booking_id)?.from_seq ?? 0 : zones.get(s.booking_id)?.to_seq ?? 0,
  }));
  const start = ((points.data ?? []) as { lat: number; lng: number }[])[0];
  const plan = start ? buildStopPlan(planStops, start) : null;
  if (!plan || plan.groups.length === 0) back(tripId, { optimized: 'none' });

  const results = await Promise.all(plan!.groups.map((g) => planOrder(g.start, g.end, g.points)));
  const ids = applyStopPlan(plan!.base, plan!.groups, results.map((r) => r.order));
  const { error } = await supabase.rpc('set_trip_stop_order', { p_trip_id: tripId, p_stop_ids: ids });
  if (error) back(tripId, { error: await errorMessage(error) });

  const moved = ids.filter((id, i) => rows[i]?.id !== id).length;
  const times = await recomputeTimes(supabase, tripId);
  const via = results.every((r) => r.source === 'geoapify') ? 'road' : 'local';
  back(tripId, times.error ? { error: times.error } : { optimized: via, moved: String(moved), times: times.approximate ? 'approximate' : 'ok' });
}

export async function createTrackingLink(
  _prev: { value: string | null; error: string | null },
  form: FormData,
): Promise<{ value: string | null; error: string | null }> {
  const { supabase } = await requireStaffCompany();
  const { data, error } = await supabase.rpc('create_tracking_link', { p_booking_id: text(form, 'booking_id') });
  if (error || typeof data !== 'string') return { value: null, error: await errorMessage(error) };
  const { headers } = await import('next/headers');
  const origin = process.env.NEXT_PUBLIC_SITE_URL ?? (await headers()).get('origin') ?? '';
  return { value: `${origin}/u/${data}`, error: null };
}
