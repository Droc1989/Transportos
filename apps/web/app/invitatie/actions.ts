'use server';

import { errorMessage, text } from '@/lib/form';
import { createClient } from '@/lib/supabase/server';

export type AcceptState = { company: string | null; role: string | null; error: string | null };

export async function acceptInvite(_prev: AcceptState, form: FormData): Promise<AcceptState> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('accept_invite', { p_code: text(form, 'code') });
  const result = data as { company?: string; role?: string } | null;
  if (error || !result?.company) return { company: null, role: null, error: await errorMessage(error) };
  return { company: result.company, role: result.role ?? null, error: null };
}
