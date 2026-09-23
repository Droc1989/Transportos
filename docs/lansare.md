# Lansarea pilotului

Pașii de la codul din repo până la prima firmă care lucrează în TransportOS. În ordine.

## 1. Supabase (baza de date și autentificarea)

- [ ] Proiect nou în regiunea **Frankfurt (eu-central-1)**: datele rămân în UE.
- [ ] `supabase link --project-ref <ref>`, apoi `supabase db push` (aplică toate migrațiile).
- [ ] Extensii: PostGIS și btree_gist se instalează din migrații; activează **pg_cron** din
      Database → Extensions și programează joburile:

```sql
select cron.schedule('refresh-public-map', '* * * * *', $$select public.refresh_public_live_trips()$$);
select cron.schedule('eta-notifications',  '* * * * *', $$select public.enqueue_eta_notifications()$$);
select cron.schedule('retention',          '15 3 * * *', $$select public.run_retention()$$);
```

      (Workerul le rulează oricum la fiecare tură; cron-ul e o plasă de siguranță.)
- [ ] Authentication → Providers: email + parolă. Confirmarea emailului: pornită.
- [ ] Authentication → URL Configuration: adresa site-ului și `/login` la redirect URLs.
- [ ] Authentication → MFA: pornit (autentificare în doi pași pentru admini).
- [ ] Contul tău: creează-l în Authentication → Users, apoi în SQL Editor:

```sql
insert into public.platform_admins (user_id) values ('<id-ul tău>');
```

## 2. Aplicația web (Vercel sau alt hosting Next.js)

- [ ] Variabile: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
      `NEXT_PUBLIC_SITE_URL` (ex. `https://app.transportos.ro`), opțional `OSRM_URL`.
- [ ] Domeniul și HTTPS.
- [ ] Intră pe `/admin` cu contul tău: trebuie să vezi panoul Super Admin.

## 2b. Site-urile firmelor

- [ ] În Supabase → Storage: verifică bucketul public `site-media` (îl creează migrația 2100).
- [ ] DNS la domeniul platformei: `*.transportos.ro` (wildcard) → hosting; la Vercel, adaugă
      domeniul wildcard (cere nameserverele Vercel pentru certificat).
- [ ] Setează `NEXT_PUBLIC_ROOT_DOMAIN=transportos.ro` și refă deploy-ul.
- [ ] Domeniu propriu pentru o firmă: firma pune CNAME `www` → `cname.vercel-dns.com` (sau
      adresa hostingului), tu adaugi domeniul în Vercel → Domains, iar firma îl scrie în
      „Site-ul firmei”.

## 3. Workerul de notificări

- [ ] Rulează `apps/worker` pe un server mic (VPS, Railway, Fly.io) cu `npm start`, sau
      `npm run once` dintr-un cron la fiecare minut.
- [ ] Variabile: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (secretă, doar pe server),
      `SITE_URL`.
- [ ] Fără Twilio, mesajele apar doar în log (bun pentru primele zile de pilot).
- [ ] Cu WhatsApp: cont Twilio, număr aprobat pentru WhatsApp Business, șabloane aprobate de
      Meta pentru mesajele inițiate de firmă; setează `TWILIO_*` și pornește funcția
      `sms_whatsapp` pentru firmele care o plătesc.

## 4. Prima firmă

1. Patronul: `/inregistrare-firma` → își face contul (email + parolă) → confirmă emailul →
   completează datele firmei și acceptă termenii.
2. Adaugă microbuzele: an, locuri, număr, poze exterior + interior, condiții, bagaj, declarația
   de asigurare. Din „Înscriere” trimite cererea.
3. Tu: `/admin/aprobari` → firma → verifici pozele (microbuzele vechi sunt marcate) → aprobi
   microbuzele, apoi firma. Patronul primește emailul de aprobare.
4. Patronul: Șoferi (cu codul de acces pentru fiecare) → Rute → Cursă nouă. Șoferii își
   completează profilul pe `/sofer`, iar patronul îl aprobă din Șoferi.

(Varianta veche rămâne pentru cazuri speciale: `/admin` → „Firmă nouă” → cod de proprietar.)
5. Din Echipa: coduri pentru dispeceri. Din Șoferi: coduri pentru șoferi.
6. Prima rezervare din „Rezervare nouă”; din „Opriri”: „Calculează orele” și „Link de urmărire”.
7. „Site-ul firmei”: text, contact, poze, rutele și mașinile de pe site, șoferii care și-au dat
   acordul scris, bifa „Site publicat”. Apoi prima știre.

## 5. Înainte de primul client real

- [ ] Contractul de abonament și acordul de prelucrare a datelor (GDPR) semnate cu firma.
- [ ] Politica de confidențialitate și termenii pe site.
- [ ] Răspunsul avocatului/ARR despre licența de intermediere, înainte de marketplace-ul public.
- [ ] Aplicația șoferului (Expo) testată pe telefoane reale. Până atunci, pilotul poate
      funcționa cu dispecerul marcând manual opririle din web.

## Verificări locale înainte de fiecare lansare

```bash
npm run check:enums && npm run typecheck && npm run test:worker && npm run build
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres npm run test:db
```

Testele cap-coadă prin API și paginile randate: `scripts/e2e/README.md`.
