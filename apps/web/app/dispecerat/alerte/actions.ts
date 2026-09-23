'use server';

import { revalidatePath } from 'next/cache';
import { requireStaffCompany } from '@/lib/company';
import { text } from '@/lib/form';

export async function acknowledgeEmergency(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const { error } = await supabase.rpc('acknowledge_emergency', { p_event_id: text(form, 'id') });
  if (error) throw error;
  revalidatePath('/dispecerat/alerte');
}

export async function resolveEmergency(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const { error } = await supabase.rpc('resolve_emergency', { p_event_id: text(form, 'id') });
  if (error) throw error;
  revalidatePath('/dispecerat/alerte');
}
