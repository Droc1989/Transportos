# ADR-0009 — Marketplace pentru clienți și plăți direct la firmă

**Stare:** acceptată · 23 septembrie 2026

## Decizie

- **Căutare publică** (`/cauta`, `search_marketplace`): toate firmele active, cu microbuze
  aprobate și funcția `marketplace_listing` (inclusă în toate planurile). Ordonare **neutră**:
  după ora plecării, apoi după distanța față de client. Nicio firmă nu plătește pentru poziție.
- **Fără colaborare între firme** în pilot: fiecare firmă transportă doar cu microbuzele ei
  aprobate; nu vinde locuri pe vehiculele altora și nu predă clienți. Clientul vede dacă firma
  are vehicul de rezervă. Un „Cere ajutor” doar pentru urgențe poate veni după pilot.
- **Prețul îl stabilește fiecare firmă**, pe persoană, pe porțiuni de rută
  (`route_template_prices`). Porțiunile fără preț se rezervă doar cu plata la șofer.
- **Contul de client** (`client_profiles`): nume și telefon. Fișa de client a firmei se leagă de
  cont; o fișă existentă, fără cont, se leagă doar dacă telefonul contului e confirmat prin SMS
  (altfel oricine ar vedea istoricul altcuiva).
- **Plăți prin Stripe Connect Standard**: fiecare firmă își conectează contul Stripe; plata se
  creează pe contul firmei (antetul `Stripe-Account`), fără `application_fee`. Banii intră direct
  la firmă; firma e vânzătorul și face rambursările.
  - Firma alege: plata integrală online, avans online (procent), plata la șofer, termenul de
    anulare online.
  - Locul e ținut 35 de minute cât clientul plătește (sesiunea Stripe expiră în 30).
  - Webhook-ul (`/api/stripe/webhook`) verifică semnătura și toleranța de timp; acțiunile din baza
    de date sunt idempotente. Plata sosită după expirarea locului e marcată „întârziată”.
  - Contul Stripe al firmei îl scrie doar sistemul (webhook sau acțiunea de conectare, după
    verificarea că utilizatorul e adminul firmei), nu firma direct.
- **Restul la destinație**: șoferul sau dispecerul înregistrează încasarea (`record_cash_payment`),
  idempotent pentru retrimiteri din aplicația șoferului.

## Consecințe

- Aplicația web are nevoie pe server de `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` și
  `SUPABASE_SERVICE_ROLE_KEY` (doar pentru webhook și conectarea contului Stripe).
- Confirmarea telefonului prin SMS se configurează în Supabase Auth.
- Licența de intermediere pentru căutarea publică trebuie confirmată de avocat/ARR înainte de lansare.
