# ADR-0007 — Site-ul public al fiecărei firme

**Stare:** acceptată · 23 septembrie 2026

## Context

Multe firme de transport pe rutele diasporei nu au site sau au unul neactualizat. Clienții
vor să vadă cine îi duce: firma, mașinile, șoferii, rutele, noutățile. Un site inclus în
TransportOS, actualizat din același loc în care firma lucrează zilnic, e un motiv puternic
de a folosi platforma.

## Decizie

- **Inclus în toate planurile** (funcția `company_website`), oprit la firmă suspendată.
- **Conținut:** prezentare (text formatat), contact și WhatsApp, rute alese de firmă (cu notă
  și „de la X €”), flota aleasă (poză, dotări, fără număr de înmatriculare), șoferii cu acord,
  știri (ciornă, publicare, programare), formular de cerere de rezervare.
- **Adrese:**
  - `/f/<slug>` pe adresa platformei, merge imediat;
  - `<slug>.<NEXT_PUBLIC_ROOT_DOMAIN>`, prin DNS wildcard;
  - domeniul propriu al firmei (`company_sites.custom_domain`), rezolvat de middleware prin
    `resolve_site_domain`, cu memorie de 5 minute.
- **Vizitatorii nu citesc tabele.** Funcțiile anonime întorc strict conținutul publicat:
  `get_company_site`, `get_site_post`, `resolve_site_domain`, `submit_booking_request`. Testul
  B0 verifică lista exactă.
- **Șoferi (GDPR):** profilul public cere acordul scris al șoferului, confirmat de admin prin
  `set_driver_public_profile` (se salvează data și cine a confirmat). Constrângerea din tabel
  blochează publicarea fără acord. Pe site apare doar prenumele și inițiala.
- **Text sigur:** textele firmelor se afișează cu `RichText` (paragrafe, titluri, liste,
  **îngroșat**, linkuri http/https cu `nofollow`). Nu se interpretează HTML: nu se poate
  injecta cod în pagină.
- **Poze:** Supabase Storage, bucket public `site-media`, JPG/PNG/WEBP de cel mult 5 MB. Fiecare
  firmă scrie doar în folderul ei (`<company_id>/…`), prin politicile din migrația 2100.
- **Cereri de rezervare:** câmp-capcană pentru roboți, maxim 5 pe oră de la același telefon și
  200 pe zi pe firmă. Dispecerul le vede cu număr în meniu și le transformă în rezervare
  precompletată; cererea se marchează automat „rezervare făcută”.

## Consecințe

- Subdomeniile cer un DNS wildcard (`*.transportos.ro`) spre hosting și certificat wildcard.
- Fiecare domeniu propriu trebuie adăugat și la hosting (ex. Vercel → Domains), ca să primească
  certificat HTTPS. Firma pune la furnizorul de domeniu un CNAME spre platformă.
- Poza de copertă și pozele din flotă sunt publice (URL public din Storage).
