'use server';

import { revalidatePath } from 'next/cache';
import { requireStaffCompany } from '@/lib/company';
import { text } from '@/lib/form';

export async function setRequestStatus(form: FormData): Promise<void> {
  const { supabase, userId } = await requireStaffCompany();
  const status = text(form, 'status');
  if (!['CONTACTED', 'CONVERTED', 'REJECTED'].includes(status)) return;
  const { error } = await supabase
    .from('booking_requests')
    .update({ status, handled_by: userId, handled_at: new Date().toISOString() })
    .eq('id', text(form, 'id'));
  if (error) throw error;
  revalidatePath('/dispecerat/cereri');
  revalidatePath('/dispecerat', 'layout');
}
