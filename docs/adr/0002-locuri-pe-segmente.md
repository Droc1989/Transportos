# ADR-0002 — Locuri pe segmente de traseu

**Stare:** acceptată · 23 septembrie 2026

## Context

Un microbuz Timișoara – München vinde același loc de mai multe ori: Ana până la Wien,
Markus de la Linz. Un simplu `available_seats` nu poate modela asta (master plan §4).
Preluările sunt însă de la adresă, iar ordinea lor se schimbă des; ele nu pot fi baza
calculului de capacitate.

## Decizie

- Fiecare cursă are **puncte fixe de traseu** (`trip_route_points`, ordonate după `seq`):
  orașe sau zone (Timișoara, Arad, Budapest, Győr, Wien, Linz, Salzburg, München).
  Segmentul `k` e porțiunea dintre punctul `k` și `k+1`.
- O rezervare ocupă locuri pe intervalul `[from_seq, to_seq)`. Fiecare loc ocupat e un rând
  în `booking_seats` cu `segment int4range`.
- **Constrângere de excludere** `booking_seats_no_overlap` (GiST): același loc, pe aceeași
  cursă, nu poate avea două rânduri active cu segmente suprapuse. E garanția finală,
  indiferent de codul aplicației.
- `book_seats` blochează rândul cursei (`for update`), eliberează rezervările `HELD` expirate,
  alege cele mai mici numere de loc libere și inserează. Rezervările pe aceeași cursă se
  execută pe rând; pe curse diferite, în paralel.
- Opririle reale (door-to-door) sunt în `trip_stops`, separat, doar pentru ordine și ETA.
  Un client e legat de cel mai apropiat punct de traseu (zonă) pentru capacitate.
- Statusul de cursă (`trip_status`) și alte tipuri noi (`member_role`, `subscription_status`,
  `payment_method`, `stop_kind`, `stop_status`) au fost adăugate aici; nu existau în master plan.

## Consecințe

- Punctele de traseu trebuie definite la crearea cursei (din șabloane de rută, în Company Admin).
- Potrivirea pe zone e aproximativă pentru adrese aflate între două puncte; ocolul exact
  în minute se calculează în aplicație, prin `RoutingProvider`.
