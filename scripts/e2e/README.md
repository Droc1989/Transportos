# Teste cap-coadă

Două scripturi, pe o bază cu migrațiile și datele din `supabase/tests/fixtures.sql`:

- `api.e2e.mts`: aceleași apeluri ca aplicațiile (`@supabase/supabase-js`): dispecer, șofer,
  client anonim și worker, inclusiv linkul din mesajul trimis;
- `pages.e2e.mjs`: paginile Next.js randate pe server, cu sesiuni de test pentru dispecer,
  proprietar, șofer și Super Admin;
- `onboarding.e2e.mjs`: înscrierea unei firme noi până la aprobare (cere `onboarding-users.sql`);
- `marketplace_e2e.py`: căutare, rezervare, avans prin Stripe, webhook, restul la destinație, cu
  browser real (Playwright, Python) și `fake-stripe.mjs` (cere `marketplace-demo.sql`);
- `landing_search_e2e.py`: căutarea de pe prima pagină → rezultate (nume fără diacritice, „Viena”,
  GPS, oraș necunoscut, „Acum”, telefon și desktop), cu browser real (Playwright, Python);
- `sites.e2e.mjs`: site-urile firmelor (conținut, text sigur, subdomeniu, domeniu propriu,
  cereri). Cere `site-demo.sql` încărcat după fixtures și build-ul web cu
  `NEXT_PUBLIC_ROOT_DOMAIN=transportos.test`.

## Fără Supabase complet (PostgREST + proxy)

`proxy.mjs` trimite `/rest/v1/*` la PostgREST și are un înlocuitor minim pentru
`/auth/v1/user`, care acceptă doar JWT-uri semnate cu `JWT_SECRET`. **Doar pentru teste.**

```bash
# baza de test: stub + migrații + fixtures (commit)
postgrest pgrst.conf &                         # db-anon-role=anon, jwt-secret=$JWT_SECRET
JWT_SECRET=... node scripts/e2e/proxy.mjs &    # :54321
SUPABASE_URL=http://127.0.0.1:54321 JWT_SECRET=... npx tsx scripts/e2e/api.e2e.mts

# pagini: build + start cu NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 și cheia anon
# generată cu: JWT_SECRET=... node scripts/e2e/jwt.mjs '{"role":"anon"}'
JWT_SECRET=... TRACKING_TOKEN=<token> node scripts/e2e/pages.e2e.mjs
```

Rulorul de roluri Postgres pentru PostgREST: `authenticator` (login, noinherit), cu
`grant anon, authenticated, service_role to authenticator`.
