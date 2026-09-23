'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { zonedLocalToUtc } from '@/lib/time';

export async function updateTrip(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, timeZone } = await requireStaffCompany();
  const id = text(form, 'id');
  const locked = text(form, 'locked') === 'true';

  // Cursă pornită: se poate schimba doar șoferul. Regula e și în baza de date.
  const changes: Record<string, unknown> = { driver_id: text(form, 'driver_id') || null };
  if (!locked) {
    const departure = zonedLocalToUtc(text(form, 'departure'), timeZone);
    if (!departure) return { error: await errorMessage(null) };
    changes.vehicle_id = text(form, 'vehicle_id');
    changes.departure_at = departure.toISOString();
    changes.title = text(form, 'title') || undefined;
  }

  const { error } = await supabase.from('trips').update(changes).eq('id', id);
  if (error) return { error: await errorMessage(error) };

  revalidatePath('/dispecerat');
  redirect('/dispecerat?updated=1');
}

export async function cancelTrip(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase } = await requireStaffCompany();
  if (form.get('confirm') !== 'on') return { error: null };
  const { data, error } = await supabase.rpc('cancel_trip', { p_trip_id: text(form, 'id') });
  if (error) return { error: await errorMessage(error) };
  revalidatePath('/dispecerat');
  redirect(`/dispecerat?cancelled=${typeof data === 'number' ? data : 0}`);
}
