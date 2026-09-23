# ADR-0006 — Fluxul șoferului, notificări, urmărire, retenție

**Stare:** acceptată · 23 septembrie 2026

## Fluxul șoferului

- Stările rezervării pe drum: `CONFIRMED` → `DRIVER_ASSIGNED` (la pornire) → `APPROACHING`
  (GPS, sub 2 km) → `ARRIVED` („Am ajuns”) → `ON_BOARD` → `COMPLETED`; sau `NO_SHOW`.
- „Nu s-a prezentat” și coborârea eliberează locul pentru restul traseului.
- Toate acțiunile sunt idempotente și nu depind de abonament: o cursă începută se termină.

## SOS (master plan §17)

- Manual: `CONFIRMED` imediat. Automat: `POSSIBLE`, cu numărătoare pe telefon; „SUNT BINE” îl
  anulează, lipsa răspunsului îl confirmă.
- Fereastră de 5 minute: semnale repetate pentru același vehicul nu creează alerte noi.
- La confirmare: vehiculul trece în `EMERGENCY`, se salvează pasagerii de la bord (vizibili doar
  personalului), apare un eveniment `INCIDENT` pe cursă.
- Sistemul nu sună la 112. Decizia o ia dispecerul.

## Detecție din GPS

- Doar pe cea mai nouă poziție (pozițiile sosite întârziat nu declanșează nimic).
- Apropiere: sub 2 km de următoarea oprire.
- Preluare ratată: vehiculul a trecut la sub 300 m de punct, apoi s-a îndepărtat cu peste 800 m
  (`PICKUP_AT_RISK`) sau 3 km (`PICKUP_MISSED`), fără ca clientul să urce. Pragurile sunt
  constante în `_process_position`; se pot muta în `company_settings` dacă firmele cer altceva.
- Alertele nu schimbă automat rezervarea; dispecerul decide.

## Notificări

- Baza de date doar pune mesajele în `notification_outbox`, o singură dată pe motiv
  (`dedupe_key`). Trimiterea e în worker, prin `NotificationProvider`.
- „Ajunge în N minute”: se trimite cel mai mic prag atins; dacă ETA crește la loc, pragurile
  mai mari nu se mai trimit.
- La anularea sau încheierea unei rezervări, mesajele netrimise se anulează.

## Linkul de urmărire

- Token de 256 de biți în URL, doar hash-ul în bază, expiră la 3 zile după plecare, unul
  singur pe rezervare (unul nou îl anulează pe cel vechi).
- Nu conține date despre alți clienți. Poziția exactă apare doar când e utilă clientului.

## Retenție

- Poziții GPS: detaliate 90 de zile, apoi una pe minut, șterse după 24 de luni.
- Notificări închise: 90 de zile. Linkuri de urmărire: șterse la expirare.
