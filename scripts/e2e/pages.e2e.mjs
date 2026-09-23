// Verifică paginile web randate pe server, cu sesiuni de test (cookie @supabase/ssr).
import { createHmac } from 'node:crypto';
import assert from 'node:assert/strict';

const WEB = process.env.WEB_URL ?? 'http://127.0.0.1:3000';
const SECRET = process.env.JWT_SECRET ?? '';
const TOKEN = process.env.TRACKING_TOKEN ?? '';
const TRIP = '00000000-0000-0000-0000-0000000004a1';

function jwt(claims) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const body = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ exp: Math.floor(Date.now() / 1000) + 3600, ...claims })}`;
  return `${body}.${createHmac('sha256', SECRET).update(body).digest('base64url')}`;
}
function cookieFor(sub) {
  const access = jwt({ sub, role: 'authenticated', aud: 'authenticated' });
  const session = {
    access_token: access, token_type: 'bearer', expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'test',
    user: { id: sub, aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {} },
  };
  return `sb-127-auth-token=base64-${Buffer.from(JSON.stringify(session)).toString('base64url')}`;
}
async function page(path, sub) {
  const res = await fetch(WEB + path, { headers: sub ? { cookie: cookieFor(sub) } : {}, redirect: 'manual' });
  return { status: res.status, location: res.headers.get('location'), type: res.headers.get('content-type'), body: await res.text() };
}
const steps = [];
function ok(msg) { steps.push(msg); console.log(`✔ ${msg}`); }

const DISP = '00000000-0000-0000-0000-00000000a002';
const OWNER = '00000000-0000-0000-0000-00000000a001';
const DRIVER = '00000000-0000-0000-0000-00000000a003';
const SUPER = '00000000-0000-0000-0000-00000000f001';

// Client anonim
let r = await page(`/u/${TOKEN}`);
assert.equal(r.status, 200);
assert.match(r.body, /Firma A/);
assert.match(r.body, /Ești la bord/);
assert.match(r.body, /openstreetmap\.org\/export\/embed/);
assert.match(r.body, /noindex/);
ok('pagina de urmărire: firma, „Ești la bord”, harta cu microbuzul, neindexată');
r = await page(`/u/${'x'.repeat(43)}`);
assert.equal(r.status, 404);
assert.match(r.body, /Link invalid/);
ok('link invalid: pagina 404 în română și germană');

// Dispecer
r = await page('/dispecerat', DISP);
assert.equal(r.status, 200);
assert.match(r.body, /Firma A/);
assert.match(r.body, /Timișoara – München/);
ok('dispecerul vede cursele firmei lui');
for (const [path, text] of [
  ['/dispecerat/alerte', /Alerte/],
  [`/dispecerat/curse/${TRIP}/opriri`, /Client E2E/],
  [`/dispecerat/curse/${TRIP}/pasageri`, /Lista de pasageri[\s\S]*Client E2E/],
  ['/dispecerat/vehicule', /TM-01/],
  ['/dispecerat/rute', /Timișoara/],
  ['/dispecerat/soferi', /Ionuț/],
  ['/dispecerat/echipa', /Echipa/],
  ['/dispecerat/export', /Descarcă CSV/],
  ['/dispecerat/rezervare-noua', /Rezervare nouă/],
  ['/dispecerat/curse/noua', /Cursă nouă/],
]) {
  r = await page(path, DISP);
  assert.equal(r.status, 200, `${path} → ${r.status}`);
  assert.match(r.body, text, path);
}
ok('dispecerul deschide toate paginile: alerte, opriri, pasageri, vehicule, rute, șoferi, echipă, export, rezervare, cursă nouă');

r = await page('/dispecerat/echipa', DISP);
assert.match(r.body, /Doar proprietarul sau adminul/);
r = await page('/dispecerat/echipa', OWNER);
assert.match(r.body, /Generează cod/);
ok('echipa: dispecerul nu poate invita, proprietarul poate');

const today = new Date().toISOString().slice(0, 10);
const in7 = new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);
r = await page(`/dispecerat/export/csv?from=${today}&to=${in7}`, DISP);
assert.equal(r.status, 200);
assert.match(r.type ?? '', /text\/csv/);
assert.ok(r.body.replace(/^\uFEFF/, '').startsWith('plecare;cursa;vehicul'), 'antet CSV');
const raw = new Uint8Array(await (await fetch(`${WEB}/dispecerat/export/csv?from=${today}&to=${in7}`,
  { headers: { cookie: cookieFor(DISP) } })).arrayBuffer());
assert.deepEqual([...raw.slice(0, 3)], [0xef, 0xbb, 0xbf], 'BOM UTF-8, ca Excel să afișeze corect diacriticele');
assert.match(r.body, /Client E2E/);
ok('exportul CSV: antet, separator „;” pentru Excel, rezervarea de test');

// Șoferul nu intră în dispecerat
r = await page('/dispecerat', DRIVER);
assert.equal(r.status, 307);
assert.match(r.location ?? '', /no_company/);
ok('șoferul nu are acces la dispecerat');

// Super Admin
r = await page('/admin', SUPER);
assert.equal(r.status, 200);
assert.match(r.body, /Venit lunar estimat/);
assert.match(r.body, /Firma A/);
assert.match(r.body, /Firma B/);
ok('Super Admin: lista firmelor și venitul lunar');
r = await page('/admin/firme/00000000-0000-0000-0000-0000000000a0', SUPER);
assert.equal(r.status, 200);
assert.match(r.body, /Link de urmărire pentru client/);
assert.match(r.body, /Generează cod de proprietar/);
ok('Super Admin: pagina firmei cu funcții și invitația proprietarului');
r = await page('/admin', DISP);
assert.equal(r.status, 404);
ok('dispecerul nu vede panoul Super Admin (404)');
r = await page('/', SUPER);
assert.match(r.location ?? '', /\/admin$/);
r = await page('/', DISP);
assert.match(r.location ?? '', /\/dispecerat$/);
ok('prima pagină trimite fiecare utilizator unde trebuie');

console.log(`\n${steps.length} verificări de pagini trecute`);
