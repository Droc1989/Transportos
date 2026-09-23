# ADR-0011 — Toate localitățile din RO, AT, DE și HU

**Stare:** acceptată · 23 septembrie 2026

## Context

Clienții pleacă din sate și comune, nu doar din cele 38 de orașe de pe coridor. Lista completă are
peste 100.000 de localități, iar multe au același nume (zeci de „Satu Nou”).

## Decizie

- **Sursa:** GeoNames (geonames.org), localitățile locuite din RO, AT, DE, HU, cu coordonate și
  județ/land/megye. Licență CC BY 4.0: sursa e menționată în pagina de rezultate (`mk.placesSource`).
- **Import:** `npm run import:places` (scripts/import-places.mjs) descarcă datele și le scrie prin
  `import_places`, doar cu cheia de sistem. Idempotent: rulat din nou, actualizează. Exclude
  cartierele, localitățile istorice sau abandonate; corectează ş/ţ în ș/ț.
- **Cele 38 de orașe** își păstrează identificatorii (rutele firmelor le folosesc) și nu sunt dublate
  de import (același nume normalizat, aceeași țară, sub 15 km).
- **Căutare** (`search_places`): fără diacritice, ß → ss, ae/oe/ue → a/o/u, denumiri uzuale
  („Viena”, „Munich”, și începutul lor), începutul numelui, nume asemănătoare (trigrame). Ordinea:
  exact, denumire uzuală, început, asemănare; apoi orașele de pe coridor, apoi populația. Maximum 20.
- **Interfață:** câmpurile de localitate au sugestii (numele + județul/regiunea). Pe prima pagină,
  câmpurile rămân cele din design; lista de sugestii e singurul element nou, aprobat de proprietar.
  Un nume cu mai multe potriviri („Satu Nou”) nu e ghicit: pagina întreabă care. Dacă printre
  potriviri e un singur oraș (de ex. „Arad”), e ales direct.
- **Căutarea curselor** folosește coordonatele localității, deci un sat de lângă traseu găsește
  microbuzul care trece pe lângă el.
- `public_places()` întoarce doar cele 38 de orașe; lista completă nu se mai trimite în pagini.

## Consecințe

- Baza de date crește cu ~100.000 de rânduri (câțiva zeci de MB, cu indexuri).
- Importul se rulează o dată la lansare și, opțional, de câteva ori pe an pentru actualizări.
- Adresa exactă (strada) rămâne text liber până la furnizorul de geocodare (pas ulterior).
