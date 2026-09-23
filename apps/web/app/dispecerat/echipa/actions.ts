'use server';

import type { MemberRole } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text } from '@/lib/form';

export async function createStaffInvite(
  _prev: { value: string | null; error: string | null },
  form: FormData,
): Promise<{ value: string | null; error: string | null }> {
  const { supabase, companyId } = await requireStaffCompany();
  const role = text(form, 'role') as MemberRole;
  const { data, error } = await supabase.rpc('create_staff_invite', { p_company_id: companyId, p_role: role });
  if (error || typeof data !== 'string') return { value: null, error: await errorMessage(error) };
  return { value: data, error: null };
}
