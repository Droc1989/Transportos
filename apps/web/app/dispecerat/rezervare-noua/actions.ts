'use server';

import { redirect } from 'next/navigation';
import { PAYMENT_METHODS, toDomainError, type PaymentMethod } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';

export type BookingFormState = { error: string | null };

function field(form: FormData, name: string) {
  return String(form.get(name) ?? '').trim();
}

export async function createBooking(_prev: BookingFormState, form: FormData): Promise<BookingFormState> {
  const { supabase, companyId } = await requireStaffCompany();
  const { t, tError } = await getT();

  const phone = field(form, 'phone');
  const name = field(form, 'name');
  const tripId = field(form, 'trip_id');
  const passengers = Number(field(form, 'passengers'));
  const fromSeq = Number(field(form, 'from_seq'));
  const toSeq = Number(field(form, 'to_seq'));
  const payment = field(form, 'payment_method') as PaymentMethod;
  const idempotencyKey = field(form, 'idempotency_key');

  if (!phone || !name || !tripId || !Number.isInteger(passengers) || passengers < 1) {
    return { error: t('booking.missing') };
  }
  if (!PAYMENT_METHODS.includes(payment)) return { error: tError(null) };

  // Clientul e identificat după telefon, în cadrul firmei.
  const { data: customer, error: customerError } = await supabase
    .from('customers')
    .upsert({ company_id: companyId, phone, full_name: name }, { onConflict: 'company_id,phone' })
    .select('id')
    .single();
  if (customerError || !customer) return { error: tError(toDomainError(customerError?.message)) };

  const { error } = await supabase.rpc('book_seats', {
    p_trip_id: tripId,
    p_customer_id: customer.id,
    p_passengers: passengers,
    p_from_seq: fromSeq,
    p_to_seq: toSeq,
    p_pickup_address: field(form, 'pickup_address') || null,
    p_pickup_notes: field(form, 'pickup_notes') || null,
    p_payment_method: payment,
    p_confirm: true,
    p_idempotency_key: idempotencyKey || null,
  });
  if (error) return { error: tError(toDomainError(error.message)) };

  // Rezervarea vine dintr-o cerere de pe site: cererea e rezolvată.
  const requestId = field(form, 'request_id');
  if (requestId) {
    await supabase
      .from('booking_requests')
      .update({ status: 'CONVERTED', handled_at: new Date().toISOString() })
      .eq('id', requestId);
  }

  redirect('/dispecerat?ok=1');
}
