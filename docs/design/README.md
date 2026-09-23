# Designul TransportOS — referință fixată

**Regula:** designul din acest folder este aprobat de proprietar și **nu se schimbă**.
Implementarea se apropie de design; designul nu se adaptează la implementare.

Nicio modificare de culori, fonturi, așezare, texte vizibile sau elemente de pe ecrane fără
aprobarea scrisă a proprietarului (Cristian). Asta include „îmbunătățiri” și „modernizări”.

## Ecranele aprobate (`ecrane/`)

| Fișier | Ecran |
|---|---|
| 01-landing-desktop.png | Prima pagină, desktop |
| 02-landing-mobil.png | Prima pagină, mobil |
| 03-client-rezultate.png | Client: rezultatele căutării, cu harta |
| 04-client-microbuz-si-sofer.png | Client: microbuzul, șoferul, recenziile |
| 05-client-rezervare.png | Client: rezervarea, cu locul ținut |
| 06-client-urmarire.png | Client: urmărirea microbuzului |
| 07-sofer-cursa-activa.png | Șofer: cursa activă, următoarea preluare |
| 08-sofer-oprire-brusca-sos.png | Șofer: „Ești în regulă?” după oprire bruscă |
| 09-dispecerat-desktop.png | Dispecerat, desktop: hartă, alerte, vehicule |
| 10-dispecerat-telefon.png | Dispecerat pe telefon |
| 11-dispecerat-rezervare-noua.png | Dispecerat: rezervare nouă |
| 12-super-admin.png | Panoul Super Admin |

Figma: https://www.figma.com/design/STNwCQjEC1fQZF1Ztm2KRF (aceleași ecrane, ca imagini de referință).

## Tokenuri fixate

Sunt în `apps/web/app/globals.css` (`:root`) și sunt verificate automat de
`npm run check:design` (în CI). Orice schimbare a lor face CI-ul să pice.

| Token | Valoare | Rol |
|---|---|---|
| `--sign-blue` | `#0b4ea2` | albastrul indicatoarelor rutiere: butoane principale, indicatorul de ETA |
| `--sign-blue-dark` | `#083a7a` | hover |
| `--accent` | `#ffc726` | galbenul: minute, locuri, numere de pași |
| `--ink` | `#0e1a2b` | text și fundal închis (dispecerat, șofer) |
| `--muted` | `#46546a` | text secundar |
| `--line` | `#c9d1db` | linii |
| `--ground` | `#eef1f4` | fundalul paginilor |
| `--danger` | `#b42318` | alerte, SOS |
| `--success` | `#0a7a47` | confirmări |
| `--font` | Overpass | tot textul |
| `--font-mono` | Overpass Mono | ore, minute, numere de înmatriculare |

## Stare (sincer)

- Tokenurile de mai sus sunt deja folosite în aplicația web.
- Paginile web existente sunt funcționale, dar **mai simple** decât ecranele aprobate (de exemplu
  dispeceratul nu are încă harta mare). Ele trebuie aduse la design (etapa 3 din
  `TransportOS-etape.md`), comparând vizual la dimensiunile originale ale ecranelor.
- Aplicațiile mobile (șofer, client) nu sunt încă construite; se construiesc după ecranele 03–08.

## Ce e permis fără aprobare

- Adaptarea la ecrane de alte dimensiuni (responsive), păstrând aceeași ierarhie și aceleași culori.
- Ecrane noi care nu există în design (ex. înscrierea firmei), **folosind aceleași tokenuri și
  componente**, marcate în PR ca „ecran nou, necesită aprobarea proprietarului”.
- Corectări de accesibilitate care nu schimbă aspectul (etichete, contrast deja respectat, focus).
