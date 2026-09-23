import { createHmac, timingSafeEqual } from 'node:crypto';

// Stripe prin API-ul REST (fără SDK). Doar pe server: folosește cheia secretă a platformei.
// Plățile se creează pe contul Stripe al firmei (Connect Standard, antetul Stripe-Account),
// deci banii intră direct la firmă; platforma nu adaugă nicio taxă.

type FormValue = string | number | boolean | null | undefined | FormObject | FormValue[];
interface FormObject { [key: string]: FormValue }

/** { line_items: [{ price_data: { currency: 'eur' } }] } → line_items[0][price_data][currency]=eur */
export function encodeForm(value: FormObject, prefix = ''): string {
  const parts: string[] = [];
  const add = (key: string, v: FormValue) => {
    if (v === null || v === undefined) return;
    if (Array.isArray(v)) v.forEach((item, i) => add(`${key}[${i}]`, item));
    else if (typeof v === 'object') for (const [k, inner] of Object.entries(v)) add(`${key}[${k}]`, inner);
    else parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(v))}`);
  };
  for (const [k, v] of Object.entries(value)) add(prefix ? `${prefix}[${k}]` : k, v);
  return parts.join('&');
}

export function stripeConfigured(): boolean {
  return !!process.env.STRIPE_SECRET_KEY;
}

export async function stripeRequest<T>(
  path: string,
  params: FormObject = {},
  opts: { account?: string; method?: 'GET' | 'POST' } = {},
): Promise<T> {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new Error('STRIPE_NOT_CONFIGURED');
  const base = process.env.STRIPE_API_BASE ?? 'https://api.stripe.com';
  const method = opts.method ?? 'POST';
  const body = encodeForm(params);
  const url = `${base}/v1/${path}${method === 'GET' && body ? `?${body}` : ''}`;
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/x-www-form-urlencoded',
      ...(opts.account ? { 'Stripe-Account': opts.account } : {}),
    },
    body: method === 'POST' ? body : undefined,
    signal: AbortSignal.timeout(15000),
  });
  const json = (await res.json()) as T & { error?: { message?: string } };
  if (!res.ok) throw new Error(`Stripe ${res.status}: ${json.error?.message ?? 'eroare'}`);
  return json;
}

export type StripeEvent = {
  id: string;
  type: string;
  account?: string;
  data: { object: Record<string, unknown> };
};

/**
 * Verifică semnătura webhook-ului (antetul Stripe-Signature: t=…,v1=…).
 * Refuză semnături greșite și mesaje mai vechi de `toleranceSeconds` (protecție la reluare).
 */
export function verifyStripeWebhook(
  payload: string,
  signatureHeader: string | null,
  secret: string,
  toleranceSeconds = 300,
  nowSeconds = Math.floor(Date.now() / 1000),
): StripeEvent {
  if (!signatureHeader || !secret) throw new Error('SIGNATURE_MISSING');
  const items = signatureHeader.split(',').map((p) => p.trim().split('='));
  const timestamp = Number(items.find(([k]) => k === 't')?.[1]);
  const signatures = items.filter(([k]) => k === 'v1').map(([, v]) => v ?? '');
  if (!Number.isFinite(timestamp) || signatures.length === 0) throw new Error('SIGNATURE_INVALID');
  if (Math.abs(nowSeconds - timestamp) > toleranceSeconds) throw new Error('SIGNATURE_EXPIRED');

  const expected = createHmac('sha256', secret).update(`${timestamp}.${payload}`).digest();
  const valid = signatures.some((sig) => {
    const given = Buffer.from(sig, 'hex');
    return given.length === expected.length && timingSafeEqual(given, expected);
  });
  if (!valid) throw new Error('SIGNATURE_INVALID');
  return JSON.parse(payload) as StripeEvent;
}

/** Pentru teste: construiește antetul de semnătură cum îl trimite Stripe. */
export function signStripePayload(payload: string, secret: string, timestamp = Math.floor(Date.now() / 1000)): string {
  const sig = createHmac('sha256', secret).update(`${timestamp}.${payload}`).digest('hex');
  return `t=${timestamp},v1=${sig}`;
}
