import { NextResponse, type NextRequest } from 'next/server';
import { stripeRequest, verifyStripeWebhook, type StripeEvent } from '@/lib/stripe';
import { createServiceClient } from '@/lib/supabase/service';

// Evenimentele Stripe (inclusiv de pe conturile conectate ale firmelor).
// Fiecare acțiune din baza de date e idempotentă: Stripe poate retrimite același eveniment.
export async function POST(request: NextRequest) {
  const payload = await request.text();
  let event: StripeEvent;
  try {
    event = verifyStripeWebhook(payload, request.headers.get('stripe-signature'), process.env.STRIPE_WEBHOOK_SECRET ?? '');
  } catch {
    return new NextResponse('invalid signature', { status: 400 });
  }

  const db = createServiceClient();
  const obj = event.data.object as Record<string, unknown>;
  let error: { message: string } | null = null;

  switch (event.type) {
    case 'checkout.session.completed':
    case 'checkout.session.async_payment_succeeded':
      if (obj.payment_status === 'paid') {
        ({ error } = await db.rpc('mark_payment_paid', { p_provider_ref: obj.id, p_amount_cents: obj.amount_total }));
      }
      break;
    case 'checkout.session.expired':
    case 'checkout.session.async_payment_failed':
      ({ error } = await db.rpc('mark_payment_expired', { p_provider_ref: obj.id }));
      break;
    case 'charge.refunded': {
      // Rambursarea o face firma din Stripe; găsim sesiunea plății după payment_intent.
      const sessions = await stripeRequest<{ data: { id: string }[] }>(
        'checkout/sessions', { payment_intent: String(obj.payment_intent ?? '') }, { method: 'GET', account: event.account });
      for (const s of sessions.data) {
        ({ error } = await db.rpc('mark_payment_refunded', { p_provider_ref: s.id }));
      }
      break;
    }
    case 'account.updated': {
      const companyId = (obj.metadata as Record<string, string> | undefined)?.company_id;
      if (companyId) {
        ({ error } = await db.rpc('set_company_stripe_account', {
          p_company_id: companyId, p_account_id: obj.id, p_charges_enabled: obj.charges_enabled === true,
        }));
      }
      break;
    }
    default:
      break;
  }

  if (error) {
    // Plată necunoscută sau sumă diferită: răspundem 200 ca Stripe să nu reîncerce la nesfârșit,
    // dar păstrăm urma în log (fără date personale).
    console.error(`[stripe] ${event.type} ${event.id}: ${error.message}`);
  }
  return NextResponse.json({ received: true });
}
