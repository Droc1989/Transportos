'use server';

import { revalidatePath } from 'next/cache';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { getT } from '@/lib/i18n';

export async function saveRoute(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, companyId } = await requireStaffCompany();
  const { t } = await getT();
  const name = text(form, 'name');
  const placeIds = form.getAll('place_id').map(String).filter(Boolean);
  if (!name || placeIds.length < 2) return { error: t('routes.minPoints') };

  const { error } = await supabase.rpc('save_route_template', {
    p_company_id: companyId,
    p_name: name,
    p_place_ids: placeIds,
  });
  if (error) return { error: await errorMessage(error) };

  revalidatePath('/dispecerat/rute');
  return { error: null };
}
