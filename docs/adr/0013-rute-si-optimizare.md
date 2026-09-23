# ADR-0013 — Orele pe drum real (Routing API) și ordinea preluărilor (Route Planner)

**Stare:** acceptată · 23 septembrie 2026 · completează ADR-0003

## Decizie

- **Orele opririlor pe drum real:** „Calculează orele” folosește, în ordine: serverul propriu OSRM
  (`OSRM_URL`), Geoapify Routing API (`GEOAPIFY_API_KEY`, aceeași cheie ca la adrese), altfel
  estimarea în linie dreaptă, marcată „aproximativ”. Rezultatele pe drum real se păstrează o zi,
  ca recalcularea aceleiași curse să nu consume din nou credite.
- **Estimarea live** („ajunge în X minute”) nu face cereri noi: pornește de la orele planificate și
  de la poziția GPS, ca să nu se consume cota gratuită.
- **„Optimizează ordinea preluărilor”:** reordonează doar opririle din aceeași zonă (aceeași oprire a
  rutei și același tip: coborârile unui punct înaintea urcărilor lui). Pe drum real cu Geoapify Route
  Planner API; fără Geoapify sau dacă nu răspunde, gratuit, cu metoda locală (cel mai apropiat vecin
  + 2-opt, în linie dreaptă). Apoi orele se recalculează automat.
- **Siguranța rezervărilor pe porțiuni:** `set_trip_stop_order` acceptă o ordine nouă doar dacă conține
  toate opririle active o singură dată, nu mută opririle deja făcute și păstrează ordinea zonelor pe
  traseu. Nicio optimizare nu poate lua un client înaintea celor de la punctele anterioare sau pune o
  coborâre înaintea urcării.
- **Cost:** optimizarea se face doar la cererea dispecerului (o cerere Route Planner pe zonă), nu
  automat; Route Planner consumă mai multe credite decât o căutare (vezi calculatorul Geoapify).

## Consecințe

- Aceeași cheie Geoapify acoperă adresele, orele și optimizarea; consumul se urmărește în contul Geoapify.
- La volum mare: OSRM propriu pentru ore (cost fix), Route Planner rămâne la cerere.
