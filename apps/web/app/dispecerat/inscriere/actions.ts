'use server';

import { revalidatePath } from 'next/cache';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, type FormState } from '@/lib/form';

export async function submitForReview(_prev: FormState): Promise<FormState> {
  const { supabase, companyId } = await requireStaffCompany({ allowPending: true });
  const { error } = await supabase.rpc('submit_company_for_review', { p_company_id: companyId });
  if (error) return { error: await errorMessage(error) };
  revalidatePath('/dispecerat/inscriere');
  return { error: null };
}
