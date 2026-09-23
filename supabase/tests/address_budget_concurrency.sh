#!/usr/bin/env bash
set -euo pipefail
: "${TEST_URL:?Setează TEST_URL local}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
psql "$TEST_URL" -v ON_ERROR_STOP=1 -q -c "update private_geocoding.budget set hits = '{}';"
for i in $(seq 1 50); do
  psql "$TEST_URL" -v ON_ERROR_STOP=1 -qAt -c 'set role service_role; select public.consume_address_budget();' >"$TMP/$i" 2>"$TMP/$i.err" &
done
wait
accepted=0
rejected=0
for i in $(seq 1 50); do
  result="$(cat "$TMP/$i")"
  if [[ "$result" == t ]]; then accepted=$((accepted + 1));
  elif [[ "$result" == f ]]; then rejected=$((rejected + 1));
  else cat "$TMP/$i.err"; echo "Răspuns neașteptat la cererea $i: $result"; exit 1; fi
done
echo "   geocodare concurentă: acceptate: $accepted, refuzate: $rejected"
[[ "$accepted" -eq 40 && "$rejected" -eq 10 ]]
psql "$TEST_URL" -v ON_ERROR_STOP=1 -q -c "update private_geocoding.budget set hits = '{}';"
