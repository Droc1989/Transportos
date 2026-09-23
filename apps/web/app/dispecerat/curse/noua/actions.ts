'use server';

import { redirect } from 'next/navigation';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { getT } from '@/lib/i18n';
import { addDaysLocal, zonedLocalToUtc } from '@/lib/time';

const MAX_WEEKS = 12;

export async function createTrips(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, timeZone } = await requireStaffCompany();
  const { t, locale } = await getT();

  const templateId = text(form, 'template_id');
  const vehicleId = text(form, 'vehicle_id');
  const driverId = text(form, 'driver_id') || null;
  const departureLocal = text(form, 'departure');
  const title = text(form, 'title') || null;
  const weeks = Math.min(Math.max(Number(text(form, 'weeks')) || 1, 1), MAX_WEEKS);

  const first = zonedLocalToUtc(departureLocal, timeZone);
  if (!templateId || !vehicleId || !first) {
    return { error: locale === 'de' ? 'Route, Fahrzeug und Abfahrt ausfüllen.' : 'Completează ruta, vehiculul și plecarea.' };
  }

  // Fiecare săptămână e o cursă separată, la aceeași oră locală.
  const failures: string[] = [];
  for (let week = 0; week < weeks; week += 1) {
    const local = addDaysLocal(departureLocal, week * 7);
    const departure = zonedLocalToUtc(local, timeZone);
    if (!departure) continue;
    const { error } = await supabase.rpc('create_trip_from_template', {
      p_template_id: templateId,
      p_vehicle_id: vehicleId,
      p_driver_id: driverId,
      p_departure_at: departure.toISOString(),
      p_title: title,
    });
    if (error) failures.push(`${local.replace('T', ' ')}: ${await errorMessage(error)}`);
  }

  if (failures.length === weeks) return { error: failures[0] ?? (await errorMessage(null)) };
  if (failures.length > 0) return { error: `${t('trip.partial')} ${failures.join(' · ')}` };
  redirect('/dispecerat?created=1');
}
