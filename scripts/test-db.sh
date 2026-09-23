#!/usr/bin/env bash
# Rulează migrațiile pe o bază curată și apoi testele SQL.
# Cere: psql și un Postgres 16 cu PostGIS (local sau serviciul din CI).
#   DATABASE_URL=postgres://user:pass@localhost:5432/postgres ./scripts/test-db.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADMIN_URL="${DATABASE_URL:?Setează DATABASE_URL}"
DB_NAME="${TEST_DB_NAME:-transportos_test}"
TEST_URL="${ADMIN_URL%/*}/${DB_NAME}"
PSQL=(psql -v ON_ERROR_STOP=1 -q -X)

echo "▶ Bază curată: ${DB_NAME}"
"${PSQL[@]}" "$ADMIN_URL" -c "drop database if exists ${DB_NAME} with (force);"
"${PSQL[@]}" "$ADMIN_URL" -c "create database ${DB_NAME};"
"${PSQL[@]}" "$TEST_URL" -c "alter database ${DB_NAME} set search_path = public, extensions;"

echo "▶ Stub Supabase (auth, roluri)"
"${PSQL[@]}" "$TEST_URL" -f "$ROOT/supabase/tests/00_supabase_stub.sql"

echo "▶ Migrații"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "   $(basename "$f")"
  "${PSQL[@]}" "$TEST_URL" -f "$f"
done

echo "▶ Teste SQL"
for f in "$ROOT"/supabase/tests/*.sql; do
  case "$(basename "$f")" in 00_supabase_stub.sql|fixtures.sql) continue ;; esac
  echo "   $(basename "$f")"
  "${PSQL[@]}" "$TEST_URL" -o /dev/null -f "$ROOT/supabase/tests/fixtures.sql" -f "$f"
done

echo "▶ Test de concurență"
TEST_URL="$TEST_URL" bash "$ROOT/supabase/tests/concurrency.sh"

echo "▶ Concurența aprobărilor pe pachet"
TEST_URL="$TEST_URL" bash "$ROOT/supabase/tests/package_concurrency.sh"
echo "▶ Concurența bugetului comun de adrese"
TEST_URL="$TEST_URL" bash "$ROOT/supabase/tests/address_budget_concurrency.sh"
echo "✔ Toate testele au trecut"
