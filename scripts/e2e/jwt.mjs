// Generează un JWT de test: node scripts/e2e/jwt.mjs '{"role":"anon"}'
import { createHmac } from 'node:crypto';
const claims = JSON.parse(process.argv[2] ?? '{"role":"anon"}');
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const body = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ exp: Math.floor(Date.now() / 1000) + 86400, ...claims })}`;
console.log(`${body}.${createHmac('sha256', process.env.JWT_SECRET ?? '').update(body).digest('base64url')}`);
