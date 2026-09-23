'use server';

import { revalidatePath } from 'next/cache';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { getT } from '@/lib/i18n';

export async function addDriver(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, companyId } = await requireStaffCompany();
  const fullName = text(form, 'full_name');
  if (!fullName) {
    const { locale } = await getT();
    return { error: locale === 'de' ? 'Bitte den Namen eingeben.' : 'Completează numele.' };
  }
  const { error } = await supabase.from('drivers').insert({
    company_id: companyId,
    full_name: fullName,
    phone: text(form, 'phone') || null,
  });
  if (error) return { error: await errorMessage(error) };
  revalidatePath('/dispecerat/soferi');
  return { error: null };
}

export async function setDriverActive(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const { error } = await supabase
    .from('drivers')
    .update({ active: text(form, 'active') === 'true' })
    .eq('id', text(form, 'id'));
  if (error) throw error;
  revalidatePath('/dispecerat/soferi');
}

export type InviteState = { code: string | null; error: string | null };

export async function createInvite(_prev: InviteState, form: FormData): Promise<InviteState> {
  const { supabase } = await requireStaffCompany();
  const { data, error } = await supabase.rpc('create_driver_invite', { p_driver_id: text(form, 'id') });
  if (error || typeof data !== 'string') return { code: null, error: await errorMessage(error) };
  revalidatePath('/dispecerat/soferi');
  return { code: data, error: null };
}

export async function unlinkDriver(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const { error } = await supabase.rpc('unlink_driver_account', { p_driver_id: text(form, 'id') });
  if (error) throw error;
  revalidatePath('/dispecerat/soferi');
}
