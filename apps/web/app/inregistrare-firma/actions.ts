'use server';

import { redirect } from 'next/navigation';
import { errorMessage, text, type FormState } from '@/lib/form';
import { createClient } from '@/lib/supabase/server';

export async function registerCompany(_prev: FormState, form: FormData): Promise<FormState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('register_company', {
    p_name: text(form, 'name'),
    p_slug: text(form, 'slug').toLowerCase(),
    p_country: text(form, 'country'),
    p_registration_no: text(form, 'registration_no'),
    p_license_no: text(form, 'license_no'),
    p_contact_phone: text(form, 'contact_phone'),
    p_accept_terms: form.get('terms') === 'on',
  });
  if (error) return { error: await errorMessage(error) };
  redirect('/dispecerat/vehicule');
}
