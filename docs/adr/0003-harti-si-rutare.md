# ADR-0003 — Hărți, rutare și costuri

**Stare:** acceptată · 23 septembrie 2026

## Decizie

- **Fără navigație integrată.** Șoferul navighează în Waze sau Google Maps (link către
  aplicație, cu următoarea oprire). TransportOS face ordinea opririlor, ETA și urmărirea.
- **Hărțile din aplicațiile native:** Google Maps SDK (utilizare gratuită nelimitată la
  data deciziei).
- **Hărțile de pe web** (dispecerat, harta publică): MapLibre cu hărți OpenStreetMap, ca
  prima pagină să nu genereze cost pe vizitator.
- **ETA și ocoluri:** server OSRM propriu (RO, HU, AT, DE), prin `OsrmRoutingProvider`.
  Doar în ultimele ~45 de minute înainte de o preluare se folosește Google Routes, cu trafic
  live, pentru notificările „ajunge în 30/10 minute”.
- **Adrese:** autocompletare și geocodare Google, prin `GeocodingProvider`.
- **Istoric GPS:** tabel partiționat lunar. Poziții detaliate 90 de zile, apoi rărite la un
  punct pe minut (job de retenție, de implementat).

## Consecințe

- Toate apelurile externe trec prin interfețele din `packages/shared/src/providers.ts`.
- În Google Cloud se setează alerte de buget și limite de utilizare pe fiecare API.
