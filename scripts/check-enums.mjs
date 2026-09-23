#!/usr/bin/env node
// Verifică faptul că enum-urile SQL și listele din packages/shared sunt identice,
// inclusiv ordinea. Rulat în CI. Folosește doar Node, fără dependențe.
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const migrationsDir = join(root, 'supabase', 'migrations');
const sql = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => readFileSync(join(migrationsDir, f), 'utf8')).join('\n');

const sqlEnums = {};
for (const m of sql.matchAll(/create type public\.(\w+) as enum\s*\(([^)]*)\)/gi)) {
  sqlEnums[m[1]] = [...m[2].matchAll(/'([^']+)'/g)].map((v) => v[1]);
}
for (const m of sql.matchAll(/alter type public\.(\w+) add value (?:if not exists )?'([^']+)'/gi)) {
  (sqlEnums[m[1]] ??= []).push(m[2]);
}

const ts = readFileSync(join(root, 'packages', 'shared', 'src', 'statuses.ts'), 'utf8');
const tsLists = {};
for (const m of ts.matchAll(/export const (\w+) = \[([^\]]*)\] as const/g)) {
  tsLists[m[1]] = [...m[2].matchAll(/'([^']+)'/g)].map((v) => v[1]);
}
const mapping = {};
for (const m of ts.match(/SQL_ENUMS = \{([\s\S]*?)\}/)[1].matchAll(/(\w+):\s*(\w+)/g)) {
  mapping[m[1]] = m[2];
}

let failed = false;
for (const [sqlName, values] of Object.entries(sqlEnums)) {
  const tsName = mapping[sqlName];
  if (!tsName) { console.error(`✗ ${sqlName} lipsește din SQL_ENUMS`); failed = true; continue; }
  const tsValues = tsLists[tsName] ?? [];
  if (JSON.stringify(values) !== JSON.stringify(tsValues)) {
    console.error(`✗ ${sqlName} diferă:\n   SQL: ${values.join(', ')}\n   TS:  ${tsValues.join(', ')}`);
    failed = true;
  }
}
for (const sqlName of Object.keys(mapping)) {
  if (!sqlEnums[sqlName]) { console.error(`✗ ${sqlName} din SQL_ENUMS nu există în migrații`); failed = true; }
}
// Codurile de eroare aruncate în SQL trebuie să existe în packages/shared/src/errors.ts,
// ca aplicațiile să le poată traduce.
const sqlCodes = new Set([...sql.matchAll(/raise exception '([A-Z_]+)'/g)].map((m) => m[1]));
const errorsTs = readFileSync(join(root, 'packages', 'shared', 'src', 'errors.ts'), 'utf8');
const tsCodes = new Set([...errorsTs.match(/DOMAIN_ERRORS = \[([\s\S]*?)\]/)[1].matchAll(/'([A-Z_]+)'/g)].map((m) => m[1]));
for (const code of sqlCodes) {
  if (!tsCodes.has(code)) { console.error(`✗ codul de eroare ${code} din SQL lipsește din DOMAIN_ERRORS`); failed = true; }
}

if (failed) process.exit(1);
console.log(`✔ ${Object.keys(sqlEnums).length} enum-uri identice între SQL și packages/shared`);
console.log(`✔ ${sqlCodes.size} coduri de eroare din SQL, toate în DOMAIN_ERRORS`);
