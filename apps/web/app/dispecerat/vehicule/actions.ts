'use server';

import { revalidatePath } from 'next/cache';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { getT } from '@/lib/i18n';

export async function addVehicle(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, companyId } = await requireStaffCompany();
  const label = text(form, 'label').toUpperCase();
  const seats = Number(text(form, 'seats'));
  if (!label || !Number.isInteger(seats) || seats < 1 || seats > 60) {
    const { locale } = await getT();
    return { error: locale === 'de' ? 'Code und Plätze (1–60) ausfüllen.' : 'Completează codul și locurile (1–60).' };
  }

  const isStandby = form.get('is_standby') === 'on';
  const { error } = await supabase.from('vehicles').insert({
    company_id: companyId,
    label,
    plate: text(form, 'plate').toUpperCase() || null,
    seats,
    is_standby: isStandby,
    status: isStandby ? 'STANDBY' : 'AVAILABLE',
  });
  if (error) return { error: await errorMessage(error) };

  revalidatePath('/dispecerat/vehicule');
  return { error: null };
}

/** Schimbă starea: rezervă ↔ flotă, service ↔ disponibil. */
export async function setVehicleState(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const id = text(form, 'id');
  const to = text(form, 'to');
  const changes =
    to === 'STANDBY'
      ? { is_standby: true, status: 'STANDBY' }
      : to === 'MAINTENANCE'
        ? { status: 'MAINTENANCE' }
        : { is_standby: false, status: 'AVAILABLE' };
  const { error } = await supabase.from('vehicles').update(changes).eq('id', id);
  if (error) throw error;
  revalidatePath('/dispecerat/vehicule');
}
