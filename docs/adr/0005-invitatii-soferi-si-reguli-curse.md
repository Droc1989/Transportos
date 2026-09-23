# ADR-0005 — Invitarea șoferilor și regulile curselor

**Stare:** acceptată · 23 septembrie 2026

## Invitații prin cod, nu prin email

- Adminul firmei generează pentru un șofer un cod de 8 caractere (`XXXX-XXXX`, fără 0/O/1/I)
  și i-l trimite pe WhatsApp sau SMS. Șoferul își face cont și introduce codul.
- Motive: nu cere cheia `service_role` pe server (invitarea prin email Supabase o cere),
  merge pentru șoferi care nu-și folosesc emailul, iar firmele trimit oricum totul pe WhatsApp.
- În bază se păstrează doar hash-ul SHA-256 al codului. Codul merge o singură dată și
  expiră în 7 zile. Un cod nou îl anulează pe cel vechi.
- Spațiu de coduri: 32⁸ ≈ 10¹². Limitarea încercărilor se face la nivel de API (rate limit
  Supabase); dacă apar abuzuri, se adaugă un tabel de încercări pe utilizator.
- Șoferul dezactivat pierde accesul la curse (`is_trip_driver` cere `active`).
  `unlink_driver_account` scoate complet legătura (telefon pierdut, plecat din firmă).

## Reguli pentru curse, în triggere

- Cursele `COMPLETED` și `CANCELLED` nu se mai modifică.
- O cursă `IN_PROGRESS` nu se anulează; pentru defecțiuni se folosește fluxul de continuitate.
  În interfață, la o cursă pornită se poate schimba doar șoferul.
- Vehiculul nu se poate schimba cu unul care are mai puține locuri decât cel mai mare număr
  de loc ocupat (`VEHICLE_TOO_SMALL`). Renumerotarea locurilor la schimbare nu e făcută încă.
- La anulare, rezervările active devin `CANCELLED` cu motivul `TRIP_CANCELLED` și locurile se
  eliberează. `cancel_trip` întoarce numărul de clienți de anunțat. Anunțarea automată vine
  odată cu workerul de notificări.
