#!/usr/bin/env bash
# Test de concurență: 10 dispeceri încearcă simultan să rezerve ultimele 2 locuri.
# Trebuie să reușească exact 2. Apoi: două inserări directe simultane pe același
# loc (ocolind funcția) — baza de date trebuie să respingă una.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
URL="${TEST_URL:?}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)
TRIP='00000000-0000-0000-0000-0000000004a1'
AS_DISP="set local role authenticated; set local \"request.jwt.claim.sub\" = '00000000-0000-0000-0000-00000000a002';"

# Date de test permanente pentru acest test (baza e recreată la fiecare rulare)
"${PSQL[@]}" "$URL" -o /dev/null -f "$DIR/fixtures.sql" -c "commit;"

# Ocupă 6 din 8 locuri pe toată cursa
"${PSQL[@]}" "$URL" -o /dev/null -c "begin; $AS_DISP
  select public.book_seats('$TRIP', '00000000-0000-0000-0000-0000000003a1', 6, 0, 7, p_confirm => true);
  commit;"

TMP="$(mktemp -d)"
for i in $(seq 1 10); do
  (
    "${PSQL[@]}" "$URL" -o /dev/null -c "begin; $AS_DISP
      select public.book_seats('$TRIP', '00000000-0000-0000-0000-0000000003a2', 1, 0, 7, p_confirm => true);
      select pg_sleep(0.2);
      commit;" >/dev/null 2>"$TMP/err_$i" && touch "$TMP/ok_$i"
  ) &
done
wait

OK=$(ls "$TMP" | grep -c '^ok_' || true)
FULL=$(cat "$TMP"/err_* 2>/dev/null | grep -c 'NOT_ENOUGH_SEATS' || true)
echo "   rezervări reușite: $OK, refuzate (NOT_ENOUGH_SEATS): $FULL"

TAKEN=$("${PSQL[@]}" "$URL" -tA -c "select count(*) from public.booking_seats where trip_id = '$TRIP' and released_at is null")
if [ "$OK" -ne 2 ] || [ "$FULL" -ne 8 ] || [ "$TAKEN" -ne 8 ]; then
  echo "TEST EȘUAT: concurență (reușite=$OK, refuzate=$FULL, locuri ocupate=$TAKEN)"; exit 1
fi

# Inserări directe simultane pe același loc liber. Ștergem rândurile locului 1
# (nu doar le eliberăm), ca inserarea să nu lovească cheia primară (booking_id, seat_no)
# și singura regulă testată să fie constrângerea de suprapunere.
"${PSQL[@]}" "$URL" -o /dev/null -c "delete from public.booking_seats
  where trip_id = '$TRIP' and seat_no = 1;"
BOOKING=$("${PSQL[@]}" "$URL" -tA -c "select id from public.bookings where trip_id = '$TRIP' limit 1")
for i in 1 2; do
  (
    "${PSQL[@]}" "$URL" -o /dev/null -c "begin;
      insert into public.booking_seats (booking_id, company_id, trip_id, seat_no, segment)
      select b.id, b.company_id, b.trip_id, 1, int4range(2 + $i, 5)
      from public.bookings b where b.trip_id = '$TRIP' order by b.id offset $i - 1 limit 1;
      select pg_sleep(0.3);
      commit;" >/dev/null 2>"$TMP/direct_err_$i" && touch "$TMP/direct_ok_$i"
  ) &
done
wait
DOK=$(ls "$TMP" | grep -c '^direct_ok_' || true)
# Două inserări simultane pe același loc pot fi refuzate în două feluri, ambele corecte:
#  - booking_seats_no_overlap: a doua tranzacție vede rândul primei după ce aceasta a terminat;
#  - deadlock detected: fiecare îl vede pe al celeilalte încă în lucru și îl așteaptă, iar
#    Postgres oprește una dintre ele. Și atunci doar una rămâne; nu există loc dublat.
DEX=$(cat "$TMP"/direct_err_* 2>/dev/null | grep -cE 'booking_seats_no_overlap|deadlock detected' || true)
# Regula care contează, verificată direct: exact un rând activ pe acest loc și aceste porțiuni.
ACTIVE=$("${PSQL[@]}" "$URL" -tA -c "select count(*) from public.booking_seats
  where trip_id = '$TRIP' and seat_no = 1 and released_at is null")
echo "   inserări directe reușite: $DOK, refuzate (constrângere sau deadlock): $DEX, rânduri active: $ACTIVE"
if [ "$DOK" -ne 1 ] || [ "$DEX" -ne 1 ] || [ "$ACTIVE" -ne 1 ]; then
  echo "TEST EȘUAT: constrângerea de excludere sub concurență"
  cat "$TMP"/direct_err_* 2>/dev/null
  exit 1
fi
rm -rf "$TMP"
