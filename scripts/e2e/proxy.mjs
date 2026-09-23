// Proxy de test: /rest/v1/* → PostgREST, plus un înlocuitor minim pentru /auth/v1/user
// (validează JWT-ul HS256 cu JWT_SECRET), ca paginile server-side să poată fi testate fără
// serviciul complet de autentificare Supabase. DOAR PENTRU TESTE.
import http from 'node:http';
import { createHmac, timingSafeEqual } from 'node:crypto';

const target = new URL(process.env.POSTGREST_URL ?? 'http://127.0.0.1:3001');
const port = Number(process.env.PORT ?? 54321);
const secret = process.env.JWT_SECRET ?? '';

function verify(token) {
  const [h, p, s] = (token ?? '').split('.');
  if (!h || !p || !s || !secret) return null;
  const expected = createHmac('sha256', secret).update(`${h}.${p}`).digest();
  const given = Buffer.from(s, 'base64url');
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  const claims = JSON.parse(Buffer.from(p, 'base64url').toString());
  return claims.exp && claims.exp * 1000 < Date.now() ? null : claims;
}

http.createServer((req, res) => {
  if (req.url?.startsWith('/auth/v1/user')) {
    const claims = verify(req.headers.authorization?.replace(/^Bearer /, ''));
    if (!claims?.sub) { res.writeHead(401, { 'Content-Type': 'application/json' }); return res.end('{"message":"invalid JWT"}'); }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ id: claims.sub, aud: 'authenticated', role: 'authenticated', email: claims.email ?? '',
      app_metadata: {}, user_metadata: {}, created_at: new Date(0).toISOString() }));
  }
  const path = (req.url ?? '/').replace(/^\/rest\/v1/, '') || '/';
  const upstream = http.request(
    { hostname: target.hostname, port: target.port, path, method: req.method, headers: { ...req.headers, host: target.host } },
    (up) => { res.writeHead(up.statusCode ?? 502, up.headers); up.pipe(res); },
  );
  upstream.on('error', (e) => { res.writeHead(502); res.end(String(e)); });
  req.pipe(upstream);
}).listen(port, () => console.log(`proxy :${port} → ${target.href}`));
