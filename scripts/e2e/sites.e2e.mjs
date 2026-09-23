// Site-urile firmelor: conținut, siguranța textului, subdomeniu, domeniu propriu, cereri.
// Cere datele de probă pentru Firma A (vezi scripts/e2e/README.md) și
// NEXT_PUBLIC_ROOT_DOMAIN=transportos.test la build.
import { createHmac } from 'node:crypto';
import http from 'node:http';
import assert from 'node:assert/strict';

const WEB = new URL(process.env.WEB_URL ?? 'http://127.0.0.1:3000');
const API = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const SECRET = process.env.JWT_SECRET ?? '';

function jwt(claims) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const body = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ exp: Math.floor(Date.now() / 1000) + 3600, ...claims })}`;
  return `${body}.${createHmac('sha256', SECRET).update(body).digest('base64url')}`;
}
function cookieFor(sub) {
  const session = { access_token: jwt({ sub, role: 'authenticated', aud: 'authenticated' }), token_type: 'bearer',
    expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'test',
    user: { id: sub, aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {} } };
  return `sb-127-auth-token=base64-${Buffer.from(JSON.stringify(session)).toString('base64url')}`;
}
// Cerere cu antet Host arbitrar (fetch nu permite schimbarea lui).
function get(path, { host, sub } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: WEB.hostname, port: WEB.port, path, method: 'GET',
      headers: { host: host ?? WEB.host, ...(sub ? { cookie: cookieFor(sub) } : {}) } }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve({ status: res.statusCode, location: res.headers.location, body }));
    });
    req.on('error', reject);
    req.end();
  });
}
const steps = [];
const ok = (m) => { steps.push(m); console.log(`✔ ${m}`); };
const OWNER = '00000000-0000-0000-0000-00000000a001';
const DISP = '00000000-0000-0000-0000-00000000a002';

// Prima pagină a site-ului
let r = await get('/f/firma-a');
assert.equal(r.status, 200);
for (const text of ['Firma A', 'Timișoara – München de 12 ani', 'De ce noi', '<strong>Preluare de la adresă</strong>',
  'Timișoara → Arad → Wien → München', 'marți și vineri', 'Wi-Fi', 'Ionuț', 'germană', 'Curse noi spre Viena',
  '+40 256 000 000', 'name="full_name"', '#C0392B']) {
  assert.ok(r.body.includes(text), `lipsește: ${text}`);
}
assert.match(r.body, /href="https:\/\/arr\.ro"[^>]*rel="nofollow noopener noreferrer"/);
assert.ok(!r.body.includes('TM01AAA'), 'numărul de înmatriculare nu apare');
assert.ok(!r.body.includes('Florin'), 'șoferul fără acord nu apare');
assert.match(r.body, /<title>Firma A – Timișoara – München de 12 ani<\/title>/);
ok('prima pagină: prezentare formatată, rută, flotă, șofer cu acord, știri, contact, formular, culoarea firmei');

// Știri
r = await get('/f/firma-a/stiri');
assert.ok(r.body.includes('Curse noi spre Viena') && !r.body.includes('O ciornă'));
r = await get('/f/firma-a/stiri/curse-noi-spre-viena');
assert.equal(r.status, 200);
assert.ok(r.body.includes('<strong>marți și vineri</strong>'));
assert.ok(!r.body.includes('<script>alert(1)</script>'), 'codul din text nu se execută');
assert.ok(r.body.includes('&lt;script&gt;alert(1)&lt;/script&gt;'), 'e afișat ca text');
r = await get('/f/firma-a/stiri/ciorna');
assert.equal(r.status, 404);
ok('știri: lista, articolul formatat, HTML-ul din text afișat ca text (fără cod), ciorna ascunsă');

r = await get('/f/firma-b');
assert.equal(r.status, 404);
ok('site nepublicat: 404');

// Subdomeniu și domeniu propriu
r = await get('/', { host: 'firma-a.transportos.test' });
assert.equal(r.status, 200);
assert.ok(r.body.includes('Firma A'));
assert.ok(r.body.includes('href="/stiri"'), 'pe subdomeniu linkurile nu au prefixul /f/');
r = await get('/stiri/curse-noi-spre-viena', { host: 'firma-a.transportos.test' });
assert.equal(r.status, 200);
ok('subdomeniu firma-a.transportos.test: site-ul și știrile, cu linkuri curate');
r = await get('/', { host: 'transport-a.test' });
assert.equal(r.status, 200);
assert.ok(r.body.includes('Firma A'));
r = await get('/', { host: 'www.transport-a.test' });
assert.equal(r.status, 200);
ok('domeniul propriu transport-a.test (și cu www) arată site-ul firmei');
r = await get('/', { host: 'necunoscut.transportos.test' });
assert.equal(r.status, 404);
r = await get('/dispecerat', { host: 'transportos.test' });
assert.equal(r.status, 307);
ok('subdomeniu necunoscut: 404; domeniul platformei rămâne aplicația');

// Cerere de pe site → dispecer → rezervare precompletată
const anon = jwt({ role: 'anon' });
const res = await fetch(`${API}/rest/v1/rpc/submit_booking_request`, {
  method: 'POST', headers: { 'Content-Type': 'application/json', apikey: anon, Authorization: `Bearer ${anon}` },
  body: JSON.stringify({ p_slug: 'firma-a', p_full_name: 'Elena Test', p_phone: '+40 733 000 111', p_from: 'Lugoj',
    p_to: 'Linz', p_travel_date: null, p_passengers: 3, p_message: 'Avem un cărucior.' }),
});
assert.equal(await res.text(), 'true');
r = await get('/dispecerat', { sub: DISP });
assert.match(r.body, /Cereri de pe site<span class="nav-badge">1<\/span>/);
r = await get('/dispecerat/cereri', { sub: DISP });
const visible = r.body.replace(/<!-- -->/g, '');
assert.ok(visible.includes('Elena Test') && visible.includes('Lugoj → Linz') && visible.includes('Avem un cărucior.'));
const link = r.body.match(/href="(\/dispecerat\/rezervare-noua\?[^"]+)"/)?.[1]?.replace(/&amp;/g, '&');
assert.ok(link, 'butonul „Fă rezervarea”');
r = await get(link, { sub: DISP });
assert.ok(r.body.includes('value="Elena Test"') && r.body.includes('value="+40733000111"') && r.body.includes('name="request_id"'));
ok('cererea ajunge la dispecer (cu număr în meniu) și deschide rezervarea precompletată');

// Editorul
r = await get('/dispecerat/site', { sub: OWNER });
assert.equal(r.status, 200);
assert.ok(r.body.includes('https://firma-a.transportos.test') && r.body.includes('https://transport-a.test'));
assert.ok(r.body.includes('name="about"') && r.body.includes('Șoferul și-a dat acordul scris'));
r = await get('/dispecerat/site', { sub: DISP });
assert.ok(r.body.includes('Doar proprietarul sau adminul'));
r = await get('/dispecerat/site/stiri', { sub: DISP });
assert.ok(r.body.includes('O ciornă') && r.body.includes('ciornă'));
ok('editorul: adresele site-ului, setări doar pentru admin, știri (și ciornele) pentru toată echipa');

console.log(`\n${steps.length} verificări de site trecute`);
