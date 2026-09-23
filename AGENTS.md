# Reguli pentru agenții AI (și pentru oameni)

Citește acest fișier înainte de orice modificare. Regulile vin din master plan (§9, §14–16)
și din deciziile din `docs/adr/`.

## Nu schimba fără ADR și aprobare

- Statusurile canonice (enum-urile din `20260923000100_extensions_and_types.sql`).
- Semnătura funcțiilor SQL publice (`book_seats`, `find_matching_trips`, `ingest_position` …).
- Regulile de acces descrise în `docs/adr/0001-tenancy-rls.md`.
- Modelul de locuri pe segmente (`docs/adr/0002-locuri-pe-segmente.md`).

Dacă o sarcină cere așa ceva: oprește-te, scrie un ADR nou în `docs/adr/` și cere aprobare.

## Baza de date

- **Nu edita o migrație deja aplicată.** Orice schimbare = migrație nouă, cu numărul
  următor (`YYYYMMDDhhmm00_descriere.sql`). Migrațiile se fac pe rând, nu în paralel.
- **Orice tabel nou de tenant are:** `company_id`, cheie unică `(id, company_id)`,
  chei străine compuse `(x_id, company_id)`, `enable row level security` și politici explicite.
- **Tabelele noi primesc teste RLS** în `supabase/tests/`: o firmă nu vede datele alteia,
  șoferul vede doar ce ține de cursa lui, Super Admin nu vede date de clienți.
- **Scrierile sensibile la concurență** (locuri, poziții, confirmări) trec prin funcții
  `security definer` cu `set search_path` fixat, care verifică explicit dreptul utilizatorului.
  Ordinea de blocare: întâi rândul cursei (`for update`), apoi rezervările.
- **Idempotență:** comenzile de rezervare, evenimentele de cursă și pozițiile GPS
  acceptă aceeași cerere de două ori fără efect dublu.
- **Enum nou sau valoare nouă:** actualizează și `packages/shared/src/statuses.ts`;
  `npm run check:enums` trebuie să treacă.
- **Datele clienților nu apar în loguri** și nu sunt vizibile pentru Super Admin.

## Aplicația web

- Accesul real e controlat de RLS, nu de interfață. Nu ascunde un buton în loc să verifici pe server.
- Funcțiile pe plan se verifică pe server cu `has_feature(company_id, key)`.
- Toate textele trec prin `lib/i18n.ts`, în română și germană.
- Erorile din SQL se traduc prin `toDomainError` + `tError`, nu se afișează mesajul brut.
- Furnizorii externi (hărți, rutare, notificări, plăți) se folosesc doar prin interfețele din
  `packages/shared/src/providers.ts`. Nu apela direct Google, OSRM sau Twilio din pagini.

## Definition of Done (master plan §16)

- [ ] Migrație nouă, aplicată curat pe bază goală (`npm run test:db`).
- [ ] RLS și drepturi testate pentru tenant și rol.
- [ ] Teste pentru logica nouă; pentru locuri, și test de concurență.
- [ ] `npm run check:enums`, `npm run typecheck`, `npm run build` trec.
- [ ] Texte în RO și DE; interfață utilizabilă pe telefon.
- [ ] Fără date personale în loguri.
- [ ] ADR și README actualizate dacă s-a schimbat o decizie.
- [ ] Un branch pe sarcină, PR, CI verde înainte de merge. Niciodată direct în producție.

## Comenzi

```bash
npm install
npm run check:enums
npm run typecheck
npm run build
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres npm run test:db
```
