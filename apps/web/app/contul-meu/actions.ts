'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { errorMessage, text } from '@/lib/form';
import { createClient } from '@/lib/supabase/server';

export async function cancelMyBooking(form: FormData): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('client_cancel_booking', { p_booking_id: text(form, 'id') });
  if (error) redirect(`/contul-meu?error=${encodeURIComponent(await errorMessage(error))}`);
  revalidatePath('/contul-meu');
}

export async function trackMyBooking(form: FormData): Promise<void> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('client_tracking_link', { p_booking_id: text(form, 'id') });
  if (error || typeof data !== 'string') redirect(`/contul-meu?error=${encodeURIComponent(await errorMessage(error))}`);
  redirect(`/u/${data}`);
}
