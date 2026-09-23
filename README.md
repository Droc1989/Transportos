# TransportOS

Rezervări, dispecerat și urmărire pentru firmele de transport persoane, colete și
mașini pe rutele România – Austria – Germania. SaaS multi-firmă: fiecare firmă
plătește abonament; banii din transport intră direct la firmă.

Acesta e scheletul MVP-ului pentru pilot (vezi „Ce e gata” mai jos).

## Structură

```
supabase/
  migrations/     schema PostgreSQL + PostGIS, RLS, funcții de domeniu
  tests/          teste SQL (izolare, rezervări, GPS, hartă publică) + test de concurență
  seed.sql        date demo pentru dezvoltare locală
packages/shared/  statusuri canonice, chei de funcții, coduri de eroare, interfețe de furnizori
apps/web/         Next.js 15: login, dispecerat, rezervare nouă (RO/DE)
apps/worker/      workerul de sistem: notificări (WhatsApp/SMS prin Twilio), ETA, hartă publică, retenție
apps/driver/      aplicația șoferului (Expo) — încă neînceput, vezi README-ul din folder
docs/adr/         deciziile de arhitectură
scripts/          rularea testelor și verificarea enum-urilor
AGENTS.md         regulile pentru agenții AI care lucrează în repo
```

## Pornire locală

Ai nevoie de Node 20+, Docker și [Supabase CLI](https://supabase.com/docs/guides/cli).

```bash
npm install
supabase init                 # o singură dată, creează supabase/config.toml
supabase start                # pornește Postgres, Auth, API local
supabase db reset             # aplică migrațiile și seed.sql

cp apps/web/.env.example apps/web/.env.local
# completează NEXT_PUBLIC_SUPABASE_ANON_KEY din `supabase status`

npm run dev                   # http://localhost:3000
```

Apoi, în Supabase Studio (http://127.0.0.1:54323):

1. Authentication → Add user (email + parolă).
2. SQL Editor, cu id-ul utilizatorului creat:

```sql
insert into public.company_members (company_id, user_id, role)
values ('11111111-1111-1111-1111-111111111111', '<id utilizator>', 'OWNER');
```

Te autentifici în aplicație și vezi cele două curse demo Timișoara – München.
Ruta „Timișoara – München prin Wien” e deja salvată, deci poți crea imediat curse noi.

## Teste

```bash
npm run check:enums     # statusurile din TS = enum-urile din SQL
npm run typecheck
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres npm run test:db
```

`npm run test:worker` rulează testele mesajelor. Testele cap-coadă prin API și verificarea
paginilor randate sunt în `scripts/e2e/` (vezi README-ul de acolo).

`test:db` cere un Postgres 16 cu PostGIS la care te poți conecta ca superuser. Scriptul
creează o bază separată `transportos_test`, o șterge la fiecare rulare și nu atinge alte baze.
În CI rulează pe imaginea `postgis/postgis:16-3.4`.

Ce verifică testele:

- o firmă nu vede și nu modifică datele altei firme;
- șoferul vede doar cursa lui și clienții de pe ea;
- Super Admin vede firmele și abonamentele, nu clienții sau rezervările;
- locurile pe segmente: același loc vândut Timișoara–Wien și Linz–München;
- nicio suprapunere, nici prin inserare directă în bază;
- 10 dispeceri simultan pe ultimele 2 locuri: reușesc exact 2;
- rezervări ținute care expiră, idempotența la dublă apăsare;
- potrivirea curselor doar în direcția bună;
- poziții GPS duplicate sau întârziate, mod „doar citire” la restanță;
- harta publică: acord, funcție din plan, poziție rotunjită și întârziată.

## Ce e gata

- Schema MVP: firme, membri, planuri și funcții, flotă, clienți, curse, puncte de traseu,
  rezervări, locuri pe segmente, opriri, poziții GPS, evenimente, audit, hartă publică.
- **Toată partea de bază de date a MVP-ului.** Lista completă a funcțiilor, pe aplicație
  (dispecer, șofer, client, worker), e în [docs/api-baza-de-date.md](docs/api-baza-de-date.md):
  rezervări pe segmente, rute și curse, opriri și ore, invitații, fluxul șoferului (pornire,
  urcare, coborâre, „nu s-a prezentat”, pauze), SOS, detecția apropierii și a preluărilor
  ratate din GPS, link de urmărire pentru client, listă de pasageri, export, coada de
  notificări, hartă publică, retenția datelor.
- Company Admin: `places` (38 de localități pe coridor, cu coordonate, fără geocodare plătită),
  rute-șablon (`save_route_template`), curse create din șabloane (`create_trip_from_template`).
- Aplicația web:
  - autentificare, lista curselor cu locurile libere, formularul „Rezervare nouă”;
  - **Vehicule**: adăugare, trecere în rezervă sau în service;
  - **Șoferi**: adăugare și dezactivare (doar proprietar sau admin);
  - **Rute**: constructor de rute din orașele de pe coridor, cu ordonare;
  - **Cursă nouă**: din rută, cu vehicul, șofer și repetare săptămânală până la 12 săptămâni,
    la aceeași oră locală și după schimbarea orei de vară/iarnă;
  - **Modificare cursă**: vehicul, șofer, oră, titlu; la cursa pornită doar șoferul;
  - **Anulare cursă**: cu confirmare, anulează rezervările și arată câți clienți trebuie anunțați;
  - **Invitarea șoferilor**: cod `XXXX-XXXX` trimis pe WhatsApp, pagini `/inregistrare` și
    `/invitatie` pentru șofer, deconectarea contului de către admin (ADR-0005);
  - **Opririle cursei**: fiecare rezervare creează automat urcarea și coborârea, puse la locul
    lor pe traseu fără să strice ordinea manuală; mutare ↑ ↓, „Ordonează automat”,
    „Calculează orele” (OSRM dacă `OSRM_URL` e setat, altfel estimare în linie dreaptă
    marcată ca aproximativă; 5 min la urcare, 3 min la coborâre).

- Web, pe lângă cele de mai sus:
  - **pagina de urmărire pentru client** `/u/[token]` (RO/DE după limba clientului, se
    actualizează singură, harta OpenStreetMap doar când e cazul, neindexată);
  - **linkul de urmărire** din „Opriri”, cu trimitere pe WhatsApp;
  - **alerte** cu numărul în meniu (SOS, preluări în pericol sau ratate), actualizate automat;
  - **lista de pasageri** gata de tipărit sau salvat PDF (A4 orizontal);
  - **export CSV** pentru contabilitate (separator „;”, diacritice corecte în Excel);
  - **echipa**: coduri de invitație pentru dispeceri și admini; `/invitatie` acceptă orice cod;
  - **Super Admin** `/admin`: firme, venit lunar estimat, firmă nouă, abonament, funcții pe
    firmă, codul pentru patron.
- `apps/worker`: trimite mesajele din coadă cu link de urmărire, în limba clientului.
- **Site-ul public al fiecărei firme** (ADR-0007): la `/f/<slug>`, `<slug>.transportos.ro` sau pe
  domeniul propriu; prezentare, rute, flotă, șoferi (doar cu acord scris), știri, formular de
  cerere. Firma îl editează din „Site-ul firmei”; cererile apar în „Cereri de pe site” și devin
  rezervări precompletate. Demo local: `/f/firma-demo`.

## Ce urmează

1. **Aplicația șoferului (Expo)**, peste funcțiile din `docs/api-baza-de-date.md`. Până e gata,
   pilotul poate merge cu opririle marcate din dispecerat.
2. **Adresele pe hartă** (autocompletare prin `GeocodingProvider`), ca orele să se calculeze
   după stradă, nu după oraș.
3. Lista de funcții pentru după pilot din conversația de planificare: prețuri pe zone, colete,
   mașini pe platformă, plăți cu card, recenzii, documente, profit pe cursă, mesaje.

Pașii de punere în funcțiune sunt în [docs/lansare.md](docs/lansare.md).

## Server de rute (OSRM)

Fără `OSRM_URL`, orele se estimează în linie dreaptă (distanță × 1,3, la 75 km/h), ca pilotul
să poată porni imediat. Pentru ore reale, pe drum, pornește OSRM cu hărțile țărilor de pe rute
(docs/adr/0003-harti-si-rutare.md) și setează `OSRM_URL` în `apps/web/.env.local`.

## Configurare în Supabase (cloud)

- Activează extensia `pg_cron` și programează harta publică (comanda e la finalul
  migrației `20260923000900_public_map.sql`).
- Programează joburile de sistem (le poate rula și un worker cu `service_role`):

```sql
select cron.schedule('refresh-public-map', '* * * * *', $$select public.refresh_public_live_trips()$$);
select cron.schedule('eta-notifications',  '* * * * *', $$select public.enqueue_eta_notifications()$$);
select cron.schedule('retention',          '15 3 * * *', $$select public.run_retention()$$);
```

`run_retention` creează și partițiile GPS pentru lunile următoare.
