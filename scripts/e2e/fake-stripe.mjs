// Stripe fals pentru testele cap-coadă: răspunde ca API-ul Stripe la apelurile aplicației și
// înregistrează ce a primit (GET /__sessions). DOAR PENTRU TESTE.
import http from 'node:http';

const port = Number(process.env.PORT ?? 12111);
const sessions = [];
let n = 0;

function parseForm(body) {
  const out = {};
  for (const part of body.split('&').filter(Boolean)) {
    const [k, v = ''] = part.split('=');
    out[decodeURIComponent(k)] = decodeURIComponent(v.replace(/\+/g, ' '));
  }
  return out;
}

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    const json = (status, obj) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    if (!req.headers.authorization?.startsWith('Bearer sk_test_')) return json(401, { error: { message: 'no key' } });
    if (req.method === 'POST' && url.pathname === '/v1/accounts') {
      return json(200, { id: `acct_fake${++n}`, metadata: parseForm(body) });
    }
    if (req.method === 'POST' && url.pathname === '/v1/account_links') {
      return json(200, { url: `http://127.0.0.1:${port}/onboarding` });
    }
    if (req.method === 'POST' && url.pathname === '/v1/checkout/sessions') {
      const form = parseForm(body);
      const id = `cs_test_fake_${Date.now()}_${++n}`;
      sessions.push({ id, account: req.headers['stripe-account'] ?? null, form });
      return json(200, { id, url: `http://127.0.0.1:${port}/pay/${id}` });
    }
    if (req.method === 'GET' && url.pathname === '/v1/checkout/sessions') return json(200, { data: [] });
    if (req.method === 'GET' && url.pathname === '/__sessions') return json(200, sessions);
    if (req.method === 'GET' && url.pathname.startsWith('/pay/')) { res.writeHead(200); return res.end('pagina de plată Stripe (falsă)'); }
    return json(404, { error: { message: `necunoscut: ${req.method} ${url.pathname}` } });
  });
}).listen(port, () => console.log(`fake stripe :${port}`));
