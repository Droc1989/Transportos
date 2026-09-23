// Test cap-coadă prin API. Folosește utilizatorii și cursa din supabase/tests/fixtures.sql.
import { createHmac } from 'node:crypto';
import assert from 'node:assert/strict';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { NotificationMessage, NotificationProvider } from '@transportos/shared';
import { runCycle } from '../../apps/worker/src/main';

const URL_ = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const SECRET = process.env.JWT_SECRET ?? '';
const TRIP = '00000000-0000-0000-0000-0000000004a1';
const VEHICLE = '00000000-0000-0000-0000-0000000001a1';

function jwt(claims: Record<string, unknown>): string {
  const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const body = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ ...claims, exp: Math.floor(Date.now() / 1000) + 3600 })}`;
  return `${body}.${createHmac('sha256', SECRET).update(body).digest('base64url')}`;
}
function client(claims: Record<string, unknown>): SupabaseClient {
  return createClient(URL_, jwt(claims), { auth: { persistSession: false, autoRefreshToken: false } });
}
async function call<T>(db: SupabaseClient, fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}
async function expectError(db: SupabaseClient, fn: string, args: Record<string, unknown>, code: string) {
  const { error } = await db.rpc(fn, args);
  assert.ok(error && error.message.includes(code), `${fn} trebuia să dea ${code}, a dat ${error?.message ?? 'nimic'}`);
}

const anon = client({ role: 'anon' });
const dispatcher = client({ role: 'authenticated', sub: '00000000-0000-0000-0000-00000000a002' });
const driver = client({ role: 'authenticated', sub: '00000000-0000-0000-0000-00000000a003' });
const otherCompany = client({ role: 'authenticated', sub: '00000000-0000-0000-0000-00000000b001' });
const system = client({ role: 'service_role' });

const steps: string[] = [];
const ok = (s: string) => { steps.push(s); console.log(`✔ ${s}`); };

// 1. Dispecerul rezervă prin API, ca în formularul „Rezervare nouă”
const { data: customer, error: cErr } = await dispatcher.from('customers')
  .upsert({ company_id: '00000000-0000-0000-0000-0000000000a0', phone: '+40700000077', full_name: 'Client E2E' },
          { onConflict: 'company_id,phone' }).select('id').single();
if (cErr) throw cErr;
const booking = await call<string>(dispatcher, 'book_seats', {
  p_trip_id: TRIP, p_customer_id: customer.id, p_passengers: 2, p_from_seq: 0, p_to_seq: 4,
  p_pickup_address: 'Timișoara, Piața Victoriei', p_confirm: true, p_idempotency_key: `e2e-${Date.now()}`,
});
ok('dispecerul creează o rezervare prin API');

const { data: seen } = await otherCompany.from('bookings').select('id').eq('id', booking);
assert.equal(seen?.length, 0);
ok('altă firmă nu vede rezervarea (RLS prin API)');

// 2. Linkul de urmărire: creat de dispecer, citit de client anonim
const token = await call<string>(dispatcher, 'create_tracking_link', { p_booking_id: booking });
const tracking = await call<{ company: string; passengers: number } | null>(anon, 'get_tracking', { p_token: token });
assert.equal(tracking?.company, 'Firma A');
assert.equal(tracking?.passengers, 2);
ok('clientul anonim deschide linkul de urmărire');
assert.equal(await call(anon, 'get_tracking', { p_token: 'x'.repeat(43) }), null);
const { error: anonErr } = await anon.from('bookings').select('id').limit(1);
assert.ok(anonErr, 'anonimul nu trebuie să citească rezervări');
ok('anonimul nu vede nimic altceva');

// 3. Șoferul: pornește cursa, trimite poziții, ajunge, clientul urcă
await expectError(dispatcher, 'claim_notifications', { p_limit: 1 }, 'permission denied');
ok('dispecerul nu poate folosi coada de mesaje');
await call(driver, 'start_trip', { p_trip_id: TRIP });
const stops = await call<{ id: string; booking_id: string; kind: string }[]>(driver, 'get_trip_stops', { p_trip_id: TRIP });
const pickup = stops.find((s) => s.booking_id === booking && s.kind === 'PICKUP');
assert.ok(pickup);
await call(driver, 'ingest_position', {
  p_vehicle_id: VEHICLE, p_lat: 45.7400, p_lng: 21.2087,
  p_recorded_at: new Date(Date.now() - 5000).toISOString(), p_speed_kmh: 40, p_heading_deg: 0, p_trip_id: TRIP,
});
const approaching = await call<{ booking_status: string }>(anon, 'get_tracking', { p_token: token });
assert.equal(approaching.booking_status, 'APPROACHING');
ok('GPS-ul șoferului marchează automat „se apropie” (vizibil și în linkul clientului)');
await call(driver, 'mark_stop_arrived', { p_stop_id: pickup.id });

// 4. Workerul trimite mesajele (confirmare + „șoferul a ajuns”), cu link nou de urmărire
const sentMessages: NotificationMessage[] = [];
const capture: NotificationProvider = { send: async (m) => { sentMessages.push(m); return { providerMessageId: 'test' }; } };
const cycle = await runCycle(system, { PUSH: capture, WHATSAPP: capture, SMS: capture }, 'https://transportos.test');
const mine = sentMessages.filter((m) => m.to === '+40700000077');
assert.ok(cycle.sent >= 2, `trimise: ${cycle.sent}`);
assert.ok(mine.some((m) => m.templateKey === 'BOOKING_CONFIRMED'));
assert.ok(mine.some((m) => m.templateKey === 'DRIVER_ARRIVED'));
ok(`workerul trimite ${cycle.sent} mesaje, inclusiv confirmarea și „șoferul a ajuns”`);
const link = mine.find((m) => m.templateKey === 'DRIVER_ARRIVED')?.params.text?.match(/\/u\/([A-Za-z0-9_-]{43})/)?.[1];
assert.ok(link, 'mesajul conține linkul de urmărire');
const fromMessage = await call<{ booking_status: string } | null>(anon, 'get_tracking', { p_token: link });
assert.equal(fromMessage?.booking_status, 'ARRIVED');
ok('linkul din mesaj funcționează pentru client');
const again = await runCycle(system, { PUSH: capture, WHATSAPP: capture, SMS: capture }, 'https://transportos.test');
assert.equal(again.sent, 0);
ok('a doua tură nu retrimite nimic');

await call(driver, 'board_passenger', { p_stop_id: pickup.id });
const onBoard = await call<{ booking_status: string; vehicle_position: unknown }>(anon, 'get_tracking', { p_token: link });
assert.equal(onBoard.booking_status, 'ON_BOARD');
assert.ok(onBoard.vehicle_position, 'la bord, clientul vede poziția');
ok('clientul urcă; linkul arată „la bord” și poziția microbuzului');

// 5. Lista de pasageri și alertele
const manifest = await call<{ full_name: string; seats: number[] }[]>(driver, 'get_passenger_manifest', { p_trip_id: TRIP });
assert.ok(manifest.some((r) => r.full_name === 'Client E2E' && r.seats.length === 2));
ok('șoferul primește lista de pasageri cu locurile');
const alerts = await call<unknown[]>(dispatcher, 'get_dispatch_alerts', { p_company_id: '00000000-0000-0000-0000-0000000000a0' });
assert.ok(Array.isArray(alerts));
ok('dispecerul citește alertele');

console.log(`\n${steps.length} pași trecuți`);
