#!/usr/bin/env bash
set -euo pipefail
URL="${TEST_URL:?}"
PSQL=(psql -v ON_ERROR_STOP=1 -q -X)
# Rulează după testul existent, care lasă fixture-urile permanente în baza izolată.
C='00000000-0000-0000-0000-0000000000a0'
"${PSQL[@]}" "$URL" -c "insert into public.vehicles(id,company_id,label,plate,seats) values
 ('00000000-0000-0000-0000-00000000e001','$C','Concurrent 1','CONC1',8),
 ('00000000-0000-0000-0000-00000000e002','$C','Concurrent 2','CONC2',8),
 ('00000000-0000-0000-0000-00000000e003','$C','Concurrent 3','CONC3',8);
 begin; set local role authenticated; set local request.jwt.claim.sub='00000000-0000-0000-0000-00000000f001';
 select public.review_vehicle('00000000-0000-0000-0000-00000000e001',true); commit;" >/dev/null
TMP="$(mktemp -d)"
for n in 2 3; do
 ("${PSQL[@]}" "$URL" -c "begin; set local role authenticated;
 set local request.jwt.claim.sub='00000000-0000-0000-0000-00000000f001';
 select public.review_vehicle('00000000-0000-0000-0000-00000000e00$n',true);
 select pg_sleep(0.2); commit;" >"$TMP/out$n" 2>"$TMP/err$n" && touch "$TMP/ok$n") &
done
wait
OK=$(find "$TMP" -name 'ok*' | wc -l)
REFUSED=$(cat "$TMP"/err* | grep -c PLAN_LIMIT_REACHED || true)
TOTAL=$("${PSQL[@]}" "$URL" -tA -c "select count(*) from public.vehicles where company_id='$C' and approval_status='APPROVED'")
echo "   aprobări concurente reușite: $OK, refuzate de pachet: $REFUSED, vehicule aprobate: $TOTAL"
if [ "$OK" -ne 1 ] || [ "$REFUSED" -ne 1 ] || [ "$TOTAL" -ne 3 ]; then cat "$TMP"/err*; exit 1; fi
