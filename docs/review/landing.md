# Landing — implementare după designul aprobat

Referințe nemodificate: docs/design/ecrane/01-landing-desktop.png și 02-landing-mobil.png.
Figma: STNwCQjEC1fQZF1Ztm2KRF, nodurile 1:2 și 1:3 (imagini raster aprobate).

Pagina publică este disponibilă la / pentru vizitatorii neautentificați. Rutarea utilizatorilor autentificați către panourile rolurilor lor rămâne neschimbată.

## Texte aprobate separat de proprietar

- Abonament: de la 130 € / lună, pe firmă, pe o singură linie; cardul rămâne 506 × 298 px la lățime de pagină 1440 px și 350 × 322 px la 390 px.
- Comision: 0%; pilot: 10 firme, maximum 10 vehicule per firmă. Înscrierea și pachetele complete sunt rezervate unui PR separat, din main.
- Datele companiei: EvaMaria Shop S.R.L., CUI 44420154, J35/2346/2020, adresa aprobată de proprietar.
- [CONDIȚII PILOT] și [EMAIL] rămân vizibile și necompletate. Emailul nu generează un mailto către o adresă inventată.
- Titlurile care menționează WhatsApp sunt păstrate exact. Nicio notificare WhatsApp/SMS nu este implementată prin acest PR.

## Separarea înscrierii

PR #6 nu modifică pagina de înscriere. Macheta de înscriere în trei pași, aprobată ulterior, va fi implementată într-un PR separat.

Nu publica landing-ul în producție cât timp există înlocuitori necompletați. PR-ul nu autorizează publicarea sau integrarea automată.

## Verificare

npm run check:enums
npm run check:design
npm run typecheck
npm run build

Comparații de browser la 1440 și 390 px, folosind build local, cu API fictiv local. Capturile și rezultatele sunt livrate separat în raportul Codex. Imaginile aprobate nu sunt modificate; sprite-ul decorativ din public/landing/reference-desktop.png este o copie identică a referinței, folosită numai pentru iconurile originale.

Formularul de căutare acceptă orașele disponibile în public_places, fără diferențiere de diacritice, și locația GPS pentru plecare. Geocodarea adreselor stradale nu este implementată: o valoare nerecunoscută trimite la căutarea existentă cu mesajul de selectare a unui oraș din listă. Datele ilustrative din panoul de plecări rămân marcate ca exemplu, nu curse reale. Textele juridice neaprobate nu sunt inventate.
