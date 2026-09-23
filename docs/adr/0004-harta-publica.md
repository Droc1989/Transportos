# ADR-0004 — Harta live publică

**Stare:** acceptată · 23 septembrie 2026

## Decizie

- Pe prima pagină apar doar cursele `IN_PROGRESS`, cu locuri libere pe porțiunea rămasă, de
  la firmele care au activat `show_on_public_map` și au funcția `public_map` în plan.
- Poziția e rotunjită la o grilă de 0,05° (~5 km) și întârziată ~7 minute. Vehiculele oprite
  (sub 5 km/h) nu apar.
- Nu se afișează șoferul, numărul de înmatriculare, pasagerii sau gradul exact de ocupare.
- Vizitatorii citesc doar tabelul `public_live_trips`, regenerat o dată pe minut de
  `refresh_public_live_trips()`. Pozițiile reale nu sunt accesibile pentru `anon`.
- Poziția exactă o vede doar clientul cu rezervare, pe linkul lui, când vehiculul se apropie.

## Consecințe

- Contractul cu firma include acordul pentru afișarea pe harta publică.
- Costul hărții nu crește cu numărul de vizitatori.
