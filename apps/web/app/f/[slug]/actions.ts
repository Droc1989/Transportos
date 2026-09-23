'use server';

import { toDomainError } from '@transportos/shared';
import { createAnonClient } from '@/lib/supabase/anon';

export type RequestState = { status: 'idle' | 'sent' | 'error' | 'limit' };

export async function submitRequest(_prev: RequestState, form: FormData): Promise<RequestState> {
  // Câmp ascuns pe care doar roboții îl completează.
  if (String(form.get('website') ?? '') !== '') return { status: 'sent' };
  const get = (k: string) => String(form.get(k) ?? '').trim();
  const { error } = await createAnonClient().rpc('submit_booking_request', {
    p_slug: get('slug'),
    p_full_name: get('full_name'),
    p_phone: get('phone'),
    p_from: get('from'),
    p_to: get('to'),
    p_travel_date: get('date') || null,
    p_passengers: Number(get('passengers')) || 1,
    p_message: get('message') || null,
    p_email: get('email') || null,
    p_locale: get('locale'),
  });
  if (!error) return { status: 'sent' };
  return { status: toDomainError(error.message) === 'REQUEST_LIMIT' ? 'limit' : 'error' };
}
