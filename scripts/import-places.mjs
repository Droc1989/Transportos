#!/usr/bin/env node
// Importă localitățile (sate, comune, orașe) din GeoNames pentru RO, AT, DE, HU în tabelul places.
// Date: https://download.geonames.org/export/dump/ — licență CC BY 4.0 (sursa se menționează pe site).
//
// Folosire:
//   SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… node scripts/import-places.mjs            # descarcă și importă
//   node scripts/import-places.mjs --dir ./date-geonames --dry-run                       # fișiere locale, fără import
// Opțiuni: --countries RO,AT,DE,HU  --dir <folder cu RO.zip… și admin1CodesASCII.txt>  --dry-run  --batch 2000
// Importul e idempotent: rulat din nou, actualizează localitățile existente (după identificatorul GeoNames).
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { inflateRawSync } from 'node:zlib';

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : def; };
const COUNTRIES = opt('countries', 'RO,AT,DE,HU').split(',').map((c) => c.trim().toUpperCase());
const DIR = opt('dir', join(process.cwd(), '.geonames'));
const DRY = args.includes('--dry-run');
const BATCH = Number(opt('batch', '2000'));
const BASE = 'https://download.geonames.org/export/dump';

// Cod de localitate GeoNames (clasa P) care NU sunt localități de sine stătătoare.
const EXCLUDED_CODES = new Set(['PPLX', 'PPLH', 'PPLQ', 'PPLW', 'PPLCH', 'PPLR', 'STLMT']);
const LATIN = /^[\p{Script=Latin}\p{M}\s\-'.’()]+$/u;

/** Citește un fișier dintr-o arhivă zip (metodele stored/deflate), fără biblioteci externe. */
export function readZipEntry(buffer, wanted) {
  let eocd = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 65557); i -= 1) {
    if (buffer.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('zip invalid');
  const count = buffer.readUInt16LE(eocd + 10);
  let p = buffer.readUInt32LE(eocd + 16);
  for (let n = 0; n < count; n += 1) {
    const method = buffer.readUInt16LE(p + 10);
    const size = buffer.readUInt32LE(p + 20);
    const nameLen = buffer.readUInt16LE(p + 28);
    const extraLen = buffer.readUInt16LE(p + 30);
    const commentLen = buffer.readUInt16LE(p + 32);
    const local = buffer.readUInt32LE(p + 42);
    const name = buffer.toString('utf8', p + 46, p + 46 + nameLen);
    if (name === wanted) {
      const start = local + 30 + buffer.readUInt16LE(local + 26) + buffer.readUInt16LE(local + 28);
      const data = buffer.subarray(start, start + size);
      if (method === 0) return data.toString('utf8');
      if (method === 8) return inflateRawSync(data).toString('utf8');
      throw new Error(`metodă zip nesuportată: ${method}`);
    }
    p += 46 + nameLen + extraLen + commentLen;
  }
  throw new Error(`${wanted} lipsește din arhivă`);
}

// GeoNames scrie uneori ş/ţ cu sedilă; în română corect e cu virgulă (ș/ț).
const fixRo = (s) => s.replace(/ş/g, 'ș').replace(/Ş/g, 'Ș').replace(/ţ/g, 'ț').replace(/Ţ/g, 'Ț');

export function kindOf(code, population) {
  if (code === 'PPLC' || code === 'PPLA' || population >= 20000) return 'city';
  if (code === 'PPLA2' || population >= 2000) return 'town';
  return 'village';
}

/** Transformă rândurile GeoNames (TSV) în rânduri pentru import_places. */
export function parseGeonames(tsv, admin1) {
  const rows = [];
  for (const line of tsv.split('\n')) {
    if (!line) continue;
    const f = line.split('\t');
    const [id, name, , alternates, lat, lng, klass, code, country, , a1] = f;
    const population = Number(f[14]) || 0;
    if (klass !== 'P' || EXCLUDED_CODES.has(code) || !COUNTRIES.includes(country)) continue;
    const ro = country === 'RO';
    const clean = ro ? fixRo(name) : name;
    const alt = population >= 50000
      ? [...new Set((alternates ?? '').split(',').map((a) => a.trim()).filter((a) => a && a !== name && LATIN.test(a) && a.length <= 60))].slice(0, 15)
      : [];
    const adminRaw = admin1.get(`${country}.${a1}`) ?? null;
    rows.push({
      source_id: id, name: clean, admin_name: adminRaw && ro ? fixRo(adminRaw) : adminRaw, country,
      kind: kindOf(code, population), population, lat: Number(lat), lng: Number(lng), alt_names: alt,
    });
  }
  return rows;
}

export function parseAdmin1(text) {
  const map = new Map();
  for (const line of text.split('\n')) {
    const [key, name] = line.split('\t');
    if (key && name) map.set(key, name.replace(/^(Județul|Judetul) /, ''));
  }
  return map;
}

async function fetchTo(url, path) {
  if (existsSync(path)) return;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`descărcare eșuată ${url}: ${res.status}`);
  writeFileSync(path, Buffer.from(await res.arrayBuffer()));
}

async function importBatch(rows) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('lipsește SUPABASE_URL sau SUPABASE_SERVICE_ROLE_KEY');
  for (let attempt = 1; ; attempt += 1) {
    const res = await fetch(`${url}/rest/v1/rpc/import_places`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_rows: rows }),
    });
    if (res.ok) return Number(await res.text());
    if (attempt >= 3) throw new Error(`import eșuat: ${res.status} ${await res.text()}`);
    await new Promise((r) => setTimeout(r, 2000 * attempt));
  }
}

async function main() {
  mkdirSync(DIR, { recursive: true });
  const adminPath = join(DIR, 'admin1CodesASCII.txt');
  await fetchTo(`${BASE}/admin1CodesASCII.txt`, adminPath);
  const admin1 = parseAdmin1(readFileSync(adminPath, 'utf8'));
  let total = 0;
  for (const cc of COUNTRIES) {
    const zipPath = join(DIR, `${cc}.zip`);
    await fetchTo(`${BASE}/${cc}.zip`, zipPath);
    const rows = parseGeonames(readZipEntry(readFileSync(zipPath), `${cc}.txt`), admin1);
    const byKind = rows.reduce((m, r) => ((m[r.kind] = (m[r.kind] ?? 0) + 1), m), {});
    console.log(`${cc}: ${rows.length} localități (${Object.entries(byKind).map(([k, v]) => `${k} ${v}`).join(', ')})`);
    if (DRY) continue;
    for (let i = 0; i < rows.length; i += BATCH) {
      total += await importBatch(rows.slice(i, i + BATCH));
      process.stdout.write(`\r   importate: ${Math.min(i + BATCH, rows.length)}/${rows.length}`);
    }
    process.stdout.write('\n');
  }
  console.log(DRY ? '✔ verificare fără import (--dry-run)' : `✔ ${total} localități importate sau actualizate`);
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('import-places.mjs')) {
  main().catch((e) => { console.error(`✗ ${e.message}`); process.exit(1); });
}
