'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requirePlatformAdmin } from '@/lib/admin';
import { errorMessage, text, type FormState } from '@/lib/form';

export async function createCompany(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase } = await requirePlatformAdmin();
  const name = text(form, 'name');
  const slug = text(form, 'slug').toLowerCase();
  if (!name || !/^[a-z0-9-]{2,60}$/.test(slug)) {
    return { error: 'Completează numele și un identificator scurt (litere mici, cifre, cratimă).' };
  }
  const { data, error } = await supabase.rpc('create_company', {
    p_name: name,
    p_slug: slug,
    p_country: text(form, 'country'),
    p_plan_id: text(form, 'plan_id') || 'PILOT',
  });
  if (error || typeof data !== 'string') return { error: await errorMessage(error) };
  revalidatePath('/admin');
  redirect(`/admin/firme/${data}`);
}

export async function updateSubscription(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase } = await requirePlatformAdmin();
  const companyId = text(form, 'company_id');
  const { error } = await supabase
    .from('company_subscriptions')
    .update({
      plan_id: text(form, 'plan_id'),
      status: text(form, 'status'),
      current_period_end: text(form, 'period_end') || null,
      updated_at: new Date().toISOString(),
    })
    .eq('company_id', companyId);
  if (error) return { error: await errorMessage(error) };
  const { error: cErr } = await supabase
    .from('companies')
    .update({ status: text(form, 'company_status') })
    .eq('id', companyId);
  if (cErr) return { error: await errorMessage(cErr) };
  revalidatePath(`/admin/firme/${companyId}`);
  revalidatePath('/admin');
  return { error: null };
}

/** Funcție pe firmă: „on” / „off” (excepție) sau „plan” (cum e în plan). */
export async function setFeature(form: FormData): Promise<void> {
  const { supabase, userId } = await requirePlatformAdmin();
  const companyId = text(form, 'company_id');
  const key = text(form, 'feature_key');
  const mode = text(form, 'mode');
  if (mode === 'plan') {
    const { error } = await supabase
      .from('company_feature_overrides')
      .delete()
      .eq('company_id', companyId)
      .eq('feature_key', key);
    if (error) throw error;
  } else {
    const { error } = await supabase.from('company_feature_overrides').upsert(
      { company_id: companyId, feature_key: key, enabled: mode === 'on', set_by: userId, set_at: new Date().toISOString() },
      { onConflict: 'company_id,feature_key' },
    );
    if (error) throw error;
  }
  revalidatePath(`/admin/firme/${companyId}`);
}

export async function createOwnerInvite(
  _prev: { value: string | null; error: string | null },
  form: FormData,
): Promise<{ value: string | null; error: string | null }> {
  const { supabase } = await requirePlatformAdmin();
  const { data, error } = await supabase.rpc('create_staff_invite', {
    p_company_id: text(form, 'company_id'),
    p_role: 'OWNER',
  });
  if (error || typeof data !== 'string') return { value: null, error: await errorMessage(error) };
  return { value: data, error: null };
}
