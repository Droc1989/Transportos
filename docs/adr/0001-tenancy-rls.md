# ADR-0001 — Multi-tenant cu RLS

**Stare:** acceptată · 23 septembrie 2026

## Context

TransportOS e folosit de mai multe firme de transport în aceeași bază de date. O greșeală
de filtrare în aplicație nu trebuie să poată arăta clienții unei firme altei firme.

## Decizie

- Fiecare tabel de tenant are `company_id`. Referințele între tabele folosesc chei străine
  compuse `(id, company_id)`, deci o cursă a firmei A nu poate folosi vehiculul firmei B
  nici printr-o eroare de cod.
- Accesul e controlat de Row Level Security, cu funcții ajutătoare
  (`is_company_staff`, `is_company_admin`, `is_trip_driver`, `is_platform_admin`, `has_feature`).
- Roluri: `OWNER`, `ADMIN`, `DISPATCHER` (personal: văd tot ce ține de firmă) și `DRIVER`
  (vede doar cursele lui și rezervările/clienții de pe ele).
- **Super Admin** (proprietarul platformei) vede firme, membri, abonamente și funcții.
  **Nu** vede clienți, rezervări sau poziții GPS. Platforma e furnizor de software; firma e
  operatorul datelor clienților ei (GDPR).
- Rezervările și pozițiile nu se inserează direct; doar prin funcții care verifică dreptul.
- Abonament în mod `READ_ONLY` sau `CANCELLED`: nu se mai creează rezervări sau curse noi.
  Cursele începute continuă: poziții, evenimente și SOS nu depind de abonament.

## Consecințe

- Orice tabel nou cere politici și teste RLS (vezi AGENTS.md).
- Funcțiile `security definer` au `search_path` fixat și verifică explicit rolul.
