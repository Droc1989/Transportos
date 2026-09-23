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

export async function saveRoutePrice(form: FormData): Promise<void> {
  const { supabase, companyId } = await requireStaffCompany();
  const from = Number(text(form, 'from_seq'));
  const to = Number(text(form, 'to_seq'));
  const price = Math.round(Number(text(form, 'price').replace(',', '.')) * 100);
  if (!(to > from) || !(price > 0)) return;
  const { error } = await supabase.from('route_template_prices').upsert(
    { template_id: text(form, 'template_id'), company_id: companyId, from_seq: from, to_seq: to, price_cents: price },
    { onConflict: 'template_id,from_seq,to_seq' });
  if (error) throw error;
  revalidatePath('/dispecerat/rute');
}

export async function deleteRoutePrice(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const { error } = await supabase.from('route_template_prices').delete()
    .eq('template_id', text(form, 'template_id')).eq('from_seq', Number(text(form, 'from_seq'))).eq('to_seq', Number(text(form, 'to_seq')));
  if (error) throw error;
  revalidatePath('/dispecerat/rute');
}
