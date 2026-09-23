// Înscrierea unei firme noi, cap-coadă: înscriere → microbuz cu poze și asigurare → trimitere →
// aprobare Super Admin → firmă activă. Cere onboarding-users.sql încărcat.
import { createHmac } from 'node:crypto';
import http from 'node:http';
import assert from 'node:assert/strict';

const WEB = new URL(process.env.WEB_URL ?? 'http://127.0.0.1:3000');
const API = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const SECRET = process.env.JWT_SECRET ?? '';
const NEW_OWNER = '00000000-0000-0000-0000-00000000c201';
const SUPER = '00000000-0000-0000-0000-00000000f001';
const DRIVER = '00000000-0000-0000-0000-00000000a003';
const DISP = '00000000-0000-0000-0000-00000000a002';

function jwt(claims) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const body = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ exp: Math.floor(Date.now() / 1000) + 3600, ...claims })}`;
  return `${body}.${createHmac('sha256', SECRET).update(body).digest('base64url')}`;
}
const token = (sub) => jwt({ sub, role: 'authenticated', aud: 'authenticated' });
function cookieFor(sub) {
  const s = { access_token: token(sub), token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    refresh_token: 'test', user: { id: sub, aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {} } };
  return `sb-127-auth-token=base64-${Buffer.from(JSON.stringify(s)).toString('base64url')}`;
}
function page(path, sub) {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: WEB.hostname, port: WEB.port, path, method: 'GET',
      headers: sub ? { cookie: cookieFor(sub) } : {} }, (res) => {
      let body = ''; res.setEncoding('utf8');
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve({ status: res.statusCode, location: res.headers.location, body: body.replace(/<!-- -->/g, '') }));
    });
    req.on('error', reject); req.end();
  });
}
async function rest(sub, path, body, { method = 'POST', prefer } = {}) {
  const t = token(sub);
  const res = await fetch(`${API}/rest/v1/${path}`, { method, body: body ? JSON.stringify(body) : undefined,
    headers: { 'Content-Type': 'application/json', apikey: t, Authorization: `Bearer ${t}`, ...(prefer ? { Prefer: prefer } : {}) } });
  const text = await res.text();
  if (!res.ok) throw new Error(`${path}: ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}
const steps = [];
const ok = (m) => { steps.push(m); console.log(`✔ ${m}`); };

// 1. Înscrierea
let r = await page('/inregistrare-firma', NEW_OWNER);
assert.equal(r.status, 200);
assert.ok(r.body.includes('name="registration_no"') && r.body.includes('name="terms"'));
const companyId = await rest(NEW_OWNER, 'rpc/register_company', { p_name: 'Transport E2E', p_slug: 'transport-e2e', p_country: 'AT',
  p_registration_no: 'FN-123', p_license_no: 'KONZ-9', p_contact_phone: '+43660111222', p_accept_terms: true });
ok('patronul își înscrie firma din pagina de înscriere');

r = await page('/dispecerat', NEW_OWNER);
assert.equal(r.status, 307); assert.match(r.location ?? '', /\/dispecerat\/inscriere$/);
r = await page('/dispecerat/rute', NEW_OWNER);
assert.match(r.location ?? '', /\/dispecerat\/inscriere$/);
r = await page('/dispecerat/inscriere', NEW_OWNER);
assert.equal(r.status, 200);
assert.ok(r.body.includes('Die Firma wird geprüft') || r.body.includes('Firma e în verificare'));
ok('firma în verificare vede doar înscrierea și microbuzele');

// 2. Microbuz cu poze, condiții, asigurare
const [vehicle] = await rest(NEW_OWNER, 'vehicles', { company_id: companyId, label: 'W-01', plate: 'W1234AB', seats: 8,
  manufacture_year: 2010, features: ['AC', 'WIFI'], luggage_pieces: 2, luggage_kg: 25, approval_status: 'APPROVED' },
  { prefer: 'return=representation' });
assert.equal(vehicle.approval_status, 'PENDING');
await rest(NEW_OWNER, 'vehicle_photos', [
  { company_id: companyId, vehicle_id: vehicle.id, kind: 'EXTERIOR', url: 'https://example.test/w01-ext.jpg' },
  { company_id: companyId, vehicle_id: vehicle.id, kind: 'INTERIOR', url: 'https://example.test/w01-int.jpg' },
]);
const future = (d) => new Date(Date.now() + d * 86400000).toISOString().slice(0, 10);
await rest(NEW_OWNER, 'rpc/declare_vehicle_insurance', { p_vehicle_id: vehicle.id, p_rca_until: future(200), p_passenger_until: future(200), p_confirm: true });
r = await page(`/dispecerat/vehicule/${vehicle.id}`, NEW_OWNER);
assert.equal(r.status, 200);
assert.ok(r.body.includes('w01-ext.jpg') && r.body.includes('w01-int.jpg'));
ok('microbuzul: rămâne „în verificare” chiar dacă firma încearcă altfel; poze, condiții, asigurare');

await rest(NEW_OWNER, 'rpc/submit_company_for_review', { p_company_id: companyId });
r = await page('/dispecerat/inscriere', NEW_OWNER);
assert.ok(r.body.includes('gesendet') || r.body.includes('trimisă'));
ok('cererea e trimisă');

// 3. Super Admin
r = await page('/admin/aprobari', SUPER);
assert.equal(r.status, 200);
assert.ok(r.body.includes('Transport E2E') && r.body.includes('mai vechi de 2012'));
r = await page(`/admin/firme/${companyId}`, SUPER);
assert.ok(r.body.includes('(sub 2012)') && r.body.includes('w01-ext.jpg') && r.body.includes('Aprobă firma'));
ok('Super Admin vede firma, pozele și microbuzul din 2010 marcat');
r = await page('/admin/aprobari', DISP);
assert.equal(r.status, 404);
await rest(SUPER, 'rpc/review_vehicle', { p_vehicle_id: vehicle.id, p_approve: true, p_note: 'Verificat telefonic' });
await rest(SUPER, 'rpc/review_company', { p_company_id: companyId, p_approve: true });
r = await page('/dispecerat', NEW_OWNER);
assert.equal(r.status, 200);
assert.ok(r.body.includes('/dispecerat/rezervare-noua'));
ok('după aprobare, firma are acces complet');

// 4. Profilul șoferului și microbuzul pe linkul clientului
r = await page('/sofer', DRIVER);
assert.equal(r.status, 200);
assert.ok(r.body.includes('name="consent"'));
ok('șoferul își deschide profilul pentru completare');

await rest(DISP, 'vehicle_photos', { company_id: '00000000-0000-0000-0000-0000000000a0',
  vehicle_id: '00000000-0000-0000-0000-0000000001a1', kind: 'EXTERIOR', url: 'https://example.test/tm01.jpg' });
const tk = process.env.TRACKING_TOKEN;
if (tk) {
  r = await page(`/u/${tk}`);
  assert.ok(r.body.includes('Microbuzul tău') && r.body.includes('tm01.jpg'));
  ok('clientul vede pozele microbuzului în linkul de urmărire');
}

console.log(`\n${steps.length} verificări de înscriere trecute`);
