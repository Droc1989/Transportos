'use server';

import { headers } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { stripeRequest } from '@/lib/stripe';
import { createServiceClient } from '@/lib/supabase/service';

export async function savePaymentSettings(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, companyId } = await requireStaffCompany();
  const row = {
    company_id: companyId,
    accepts_full: form.get('accepts_full') === 'on',
    accepts_deposit: form.get('accepts_deposit') === 'on',
    deposit_percent: Number(text(form, 'deposit_percent')) || 20,
    accepts_cash: form.get('accepts_cash') === 'on',
    cancel_until_hours: Number(text(form, 'cancel_until_hours')) || 0,
  };
  const { data: existing } = await supabase.from('company_payment_settings').select('company_id').eq('company_id', companyId).maybeSingle();
  const { error } = existing
    ? await supabase.from('company_payment_settings').update({ ...row, updated_at: new Date().toISOString() }).eq('company_id', companyId)
    : await supabase.from('company_payment_settings').insert(row);
  if (error) return { error: await errorMessage(error) };
  revalidatePath('/dispecerat/plati');
  return { error: null };
}

/** Creează (o singură dată) contul Stripe Standard al firmei și trimite adminul la înregistrarea Stripe. */
export async function connectStripe(): Promise<void> {
  const { supabase, companyId, isAdmin } = await requireStaffCompany();
  if (!isAdmin) redirect('/dispecerat/plati');
  const { data: settings } = await supabase.from('company_payment_settings')
    .select('stripe_account_id').eq('company_id', companyId).maybeSingle<{ stripe_account_id: string | null }>();
  const { data: company } = await supabase.from('companies').select('contact_email, country').eq('id', companyId)
    .single<{ contact_email: string | null; country: string }>();

  let accountId = settings?.stripe_account_id ?? null;
  if (!accountId) {
    const account = await stripeRequest<{ id: string }>('accounts', {
      type: 'standard',
      country: company?.country ?? 'RO',
      email: company?.contact_email ?? undefined,
      metadata: { company_id: companyId },
    });
    accountId = account.id;
    // Contul se leagă de firmă cu cheia de sistem, după ce am verificat că utilizatorul e admin.
    const { error } = await createServiceClient().rpc('set_company_stripe_account', {
      p_company_id: companyId, p_account_id: accountId, p_charges_enabled: false,
    });
    if (error) throw error;
  }
  const origin = process.env.NEXT_PUBLIC_SITE_URL ?? (await headers()).get('origin') ?? '';
  const link = await stripeRequest<{ url: string }>('account_links', {
    account: accountId,
    type: 'account_onboarding',
    refresh_url: `${origin}/dispecerat/plati`,
    return_url: `${origin}/dispecerat/plati?stripe=return`,
  });
  redirect(link.url);
}
