'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import type { StopKind } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text } from '@/lib/form';
import { routeLegs } from '@/lib/routing';
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
export async function computeTimes(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const tripId = text(form, 'trip_id');

  const [trip, points, stops] = await Promise.all([
    supabase.from('trips').select('departure_at').eq('id', tripId).single<{ departure_at: string }>(),
    supabase.rpc('get_trip_route_points', { p_trip_id: tripId }),
    supabase.rpc('get_trip_stops', { p_trip_id: tripId }),
  ]);
  if (trip.error || points.error || stops.error) {
    back(tripId, { error: await errorMessage(trip.error ?? points.error ?? stops.error) });
  }

  const start = ((points.data ?? []) as { lat: number; lng: number }[])[0];
  const list = ((stops.data ?? []) as StopRow[]).filter((s) => s.lat !== null && s.lng !== null);
  if (!start || list.length === 0) back(tripId);

  const waypoints = [start, ...list].map((p) => ({ lat: p!.lat as number, lng: p!.lng as number }));
  const result = await routeLegs(waypoints);
  const times = computeSchedule(new Date(trip.data!.departure_at), result.legs, list.map((s) => s.kind));

  const { error } = await supabase.rpc('set_stop_planned_times', {
    p_trip_id: tripId,
    p_stop_ids: list.map((s) => s.id),
    p_times: times.map((d) => d.toISOString()),
  });
  revalidatePath(`/dispecerat/curse/${tripId}/opriri`);
  if (error) back(tripId, { error: await errorMessage(error) });
  back(tripId, { times: result.approximate ? 'approximate' : 'ok' });
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
