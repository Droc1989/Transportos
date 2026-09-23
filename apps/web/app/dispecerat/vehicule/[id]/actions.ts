'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { VEHICLE_FEATURES, VEHICLE_PHOTO_KINDS } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { getT } from '@/lib/i18n';
import { uploadSiteImage } from '@/lib/upload';

function back(id: string): never {
  revalidatePath(`/dispecerat/vehicule/${id}`);
  revalidatePath('/dispecerat/inscriere');
  redirect(`/dispecerat/vehicule/${id}?saved=1`);
}

export async function saveVehicleDetails(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase } = await requireStaffCompany({ allowPending: true });
  const id = text(form, 'id');
  const num = (k: string) => { const n = Number(text(form, k)); return text(form, k) === '' || !Number.isFinite(n) ? null : n; };
  const features = form.getAll('features').map(String).filter((f) => (VEHICLE_FEATURES as readonly string[]).includes(f));
  const { error } = await supabase.from('vehicles').update({
    label: text(form, 'label').toUpperCase(),
    plate: text(form, 'plate').toUpperCase() || null,
    seats: num('seats'),
    manufacture_year: num('manufacture_year'),
    features,
    luggage_pieces: num('luggage_pieces'),
    luggage_kg: num('luggage_kg'),
    public_description: text(form, 'public_description') || null,
  }).eq('id', id);
  if (error) return { error: await errorMessage(error) };
  back(id);
}

export async function uploadVehiclePhotos(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, companyId } = await requireStaffCompany({ allowPending: true });
  const { t } = await getT();
  const id = text(form, 'id');
  const kind = text(form, 'kind');
  if (!(VEHICLE_PHOTO_KINDS as readonly string[]).includes(kind)) return { error: await errorMessage(null) };
  const files = form.getAll('photos').filter((f): f is File => f instanceof File && f.size > 0).slice(0, 6);
  try {
    for (const [i, file] of files.entries()) {
      const url = await uploadSiteImage(supabase, companyId, file, 'fleet', id);
      if (!url) continue;
      const { error } = await supabase.from('vehicle_photos').insert({ company_id: companyId, vehicle_id: id, kind, url, sort: i });
      if (error) return { error: await errorMessage(error) };
    }
  } catch (e) {
    return { error: (e as Error).message.startsWith('IMAGE_') ? t('site.imageError') : await errorMessage(e as { message?: string }) };
  }
  back(id);
}

export async function deleteVehiclePhoto(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany({ allowPending: true });
  const { error } = await supabase.from('vehicle_photos').delete().eq('id', text(form, 'photo_id'));
  if (error) throw error;
  back(text(form, 'id'));
}

export async function declareInsurance(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase } = await requireStaffCompany({ allowPending: true });
  const id = text(form, 'id');
  const { error } = await supabase.rpc('declare_vehicle_insurance', {
    p_vehicle_id: id,
    p_rca_until: text(form, 'rca_valid_until') || null,
    p_passenger_until: text(form, 'passenger_insurance_until') || null,
    p_confirm: form.get('confirm') === 'on',
  });
  if (error) return { error: await errorMessage(error) };
  back(id);
}
