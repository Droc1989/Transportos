'use server';

import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { errorMessage, text, type FormState } from '@/lib/form';
import { stripeRequest } from '@/lib/stripe';
import { createClient } from '@/lib/supabase/server';

export async function saveClientProfile(_prev: FormState, form: FormData): Promise<FormState> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/login');
  const phone = text(form, 'phone').replace(/[^\d+]/g, '');
  const { error } = await supabase.from('client_profiles').upsert(
    { user_id: user.id, full_name: text(form, 'full_name'), phone, updated_at: new Date().toISOString() },
    { onConflict: 'user_id' });
  if (error) return { error: await errorMessage(error) };
  redirect(text(form, 'back') || '/cauta');
}

type BookResult = { booking_id: string; payment_id: string | null; amount_due_now_cents: number | null;
  currency: string; stripe_account_id: string | null; repeated: boolean };

export async function bookSeat(_prev: FormState, form: FormData): Promise<FormState> {
  const supabase = await createClient();
  const payment = text(form, 'payment');
  const { data, error } = await supabase.rpc('book_marketplace', {
    p_trip_id: text(form, 'trip_id'),
    p_from_seq: Number(text(form, 'from_seq')),
    p_to_seq: Number(text(form, 'to_seq')),
    p_passengers: Number(text(form, 'pax')),
    p_pickup_address: text(form, 'pickup_address'),
    p_pickup_notes: text(form, 'pickup_notes') || null,
    p_payment: payment,
    p_idempotency_key: text(form, 'idempotency_key'),
  });
  if (error) return { error: await errorMessage(error) };
  const r = data as BookResult;
  if (!r.payment_id || r.repeated) redirect('/contul-meu?ok=1');

  // Plata online: sesiune Stripe Checkout pe contul firmei (banii intră direct la firmă).
  const origin = process.env.NEXT_PUBLIC_SITE_URL ?? (await headers()).get('origin') ?? '';
  const session = await stripeRequest<{ id: string; url: string }>('checkout/sessions', {
    mode: 'payment',
    client_reference_id: r.payment_id,
    metadata: { payment_id: r.payment_id, booking_id: r.booking_id },
    expires_at: Math.floor(Date.now() / 1000) + 30 * 60,
    success_url: `${origin}/contul-meu?paid=1`,
    cancel_url: `${origin}/contul-meu?cancelled=1`,
    line_items: [{
      quantity: 1,
      price_data: {
        currency: r.currency.toLowerCase(),
        unit_amount: r.amount_due_now_cents ?? 0,
        product_data: { name: `${payment === 'DEPOSIT' ? 'Avans' : 'Bilet'} – ${text(form, 'label')}` },
      },
    }],
  }, { account: r.stripe_account_id ?? undefined });
  const { error: attachError } = await supabase.rpc('attach_payment_session', { p_payment_id: r.payment_id, p_session_id: session.id });
  if (attachError) return { error: await errorMessage(attachError) };
  redirect(session.url);
}
