# ADR-0012 — Adrese (stradă și număr) cu sugestii

**Stare:** acceptată · 23 septembrie 2026

## Decizie

- **Varianta cea mai ieftină:** adresele vin de la un serviciu extern, nu din baza noastră (milioane
  de adrese). Pentru pilot, **Geoapify, planul gratuit** (3.000 de cereri pe zi, date OpenStreetMap,
  licență ODbL: coordonatele se pot păstra, cu mențiunea sursei). Planul gratuit cere mențiunea
  „Powered by Geoapify” și a OpenStreetMap, afișate sub sugestii.
- **Când volumul depășește planul gratuit:** serviciu propriu **Photon** (tot OpenStreetMap) pe un
  server închiriat, cost fix, fără plată per căutare. Trecerea e doar o setare (`PHOTON_URL`);
  codul folosește adaptorul `GeocodingProvider`.
- **Economia de cereri:** sugestiile pornesc după 3 litere și 350 ms de pauză; căutările sunt limitate
  la cele 4 țări și orientate spre localitatea aleasă; rezultatele se păstrează 10 minute pe server;
  maximum 40 de cereri pe minut de la aceeași adresă IP.
- **Unde:** adresa de preluare la rezervarea clientului (orientată spre localitatea din căutare) și
  preluarea + destinația la rezervarea dispecerului (orientate spre opririle cursei).
- **Punctul exact** se salvează la rezervare: dispecerul prin `book_seats` (coordonate de preluare și
  destinație), clientul prin `set_my_pickup_point`, acceptat doar la cel mult 50 km de traseu și doar
  înainte de plecare. Punctul respins nu anulează rezervarea: rămâne adresa text.
- **Fără serviciu configurat** sau când serviciul nu răspunde, câmpul rămâne text liber, ca înainte.
  La fel pentru satele fără nume de străzi („casa verde de lângă biserică”).

## Consecințe

- Cont Geoapify (gratuit) și cheia `GEOAPIFY_API_KEY` pe serverul web.
- Consumul se urmărește în contul Geoapify; la apropierea de 3.000/zi se trece pe Photon.
