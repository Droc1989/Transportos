import assert from 'node:assert/strict';
import { test } from 'node:test';
import { encodeForm, signStripePayload, verifyStripeWebhook } from './stripe';

const secret = 'whsec_test_123';
const payload = JSON.stringify({ id: 'evt_1', type: 'checkout.session.completed', data: { object: { id: 'cs_1' } } });

test('semnătură corectă: evenimentul e acceptat', () => {
  const event = verifyStripeWebhook(payload, signStripePayload(payload, secret), secret);
  assert.equal(event.type, 'checkout.session.completed');
});

test('conținut modificat după semnare: refuzat', () => {
  const header = signStripePayload(payload, secret);
  assert.throws(() => verifyStripeWebhook(payload.replace('cs_1', 'cs_2'), header, secret), /SIGNATURE_INVALID/);
});

test('alt secret: refuzat', () => {
  assert.throws(() => verifyStripeWebhook(payload, signStripePayload(payload, 'whsec_alt'), secret), /SIGNATURE_INVALID/);
});

test('mesaj vechi (reluat): refuzat', () => {
  const old = Math.floor(Date.now() / 1000) - 3600;
  assert.throws(() => verifyStripeWebhook(payload, signStripePayload(payload, secret, old), secret), /SIGNATURE_EXPIRED/);
});

test('fără antet: refuzat', () => {
  assert.throws(() => verifyStripeWebhook(payload, null, secret), /SIGNATURE_MISSING/);
});

test('codarea parametrilor ca la Stripe', () => {
  assert.equal(
    encodeForm({ mode: 'payment', line_items: [{ quantity: 1, price_data: { currency: 'eur', unit_amount: 1200 } }], metadata: { payment_id: 'p1' } }),
    'mode=payment&line_items%5B0%5D%5Bquantity%5D=1&line_items%5B0%5D%5Bprice_data%5D%5Bcurrency%5D=eur&line_items%5B0%5D%5Bprice_data%5D%5Bunit_amount%5D=1200&metadata%5Bpayment_id%5D=p1',
  );
});
