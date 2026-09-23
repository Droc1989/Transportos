import assert from 'node:assert/strict';
import { test } from 'node:test';
import { deflateRawSync } from 'node:zlib';
import { kindOf, parseAdmin1, parseGeonames, parsePostcodes, readZipEntry } from './import-places.mjs';

// Arhivă zip minimă (o intrare, comprimată), ca fișierele GeoNames.
function makeZip(name, text) {
  const data = deflateRawSync(Buffer.from(text, 'utf8'));
  const n = Buffer.from(name);
  const local = Buffer.alloc(30); local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(8, 8);
  local.writeUInt32LE(data.length, 18); local.writeUInt32LE(Buffer.byteLength(text), 22); local.writeUInt16LE(n.length, 26);
  const central = Buffer.alloc(46); central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(8, 10);
  central.writeUInt32LE(data.length, 20); central.writeUInt32LE(Buffer.byteLength(text), 24); central.writeUInt16LE(n.length, 28);
  central.writeUInt32LE(0, 42);
  const cdOffset = local.length + n.length + data.length;
  const eocd = Buffer.alloc(22); eocd.writeUInt32LE(0x06054b50, 0); eocd.writeUInt16LE(1, 8); eocd.writeUInt16LE(1, 10);
  eocd.writeUInt32LE(central.length + n.length, 12); eocd.writeUInt32LE(cdOffset, 16);
  return Buffer.concat([local, n, data, central, n, eocd]);
}

const row = (id, name, cls, code, cc, a1, pop, alt = '') =>
  [id, name, name, alt, '45.9', '21.07', cls, code, cc, '', a1, '', '', '', String(pop), '', '', 'Europe/Bucharest', '2020-01-01'].join('\t');

test('citește fișierul din arhiva zip', () => {
  assert.equal(readZipEntry(makeZip('RO.txt', 'salut, ș și ț'), 'RO.txt'), 'salut, ș și ț');
  assert.throws(() => readZipEntry(makeZip('RO.txt', 'x'), 'AT.txt'), /lipsește/);
});

test('păstrează doar localitățile locuite, cu județul corect', () => {
  const admin1 = parseAdmin1('RO.36\tTimiş\tTimis\t1\nAT.03\tNiederösterreich\tLower Austria\t2\n');
  const rows = parseGeonames([
    row('1', 'Bulgăruş', 'P', 'PPL', 'RO', '36', 900),
    row('2', 'Cartier', 'P', 'PPLX', 'RO', '36', 0),
    row('3', 'Sat părăsit', 'P', 'PPLQ', 'RO', '36', 0),
    row('4', 'Râul Timiş', 'H', 'STM', 'RO', '36', 0),
    row('5', 'Neudorf', 'P', 'PPL', 'AT', '03', 500),
    row('6', 'Paris', 'P', 'PPLC', 'FR', 'A8', 2000000),
  ].join('\n'), admin1);
  assert.deepEqual(rows.map((r) => r.name), ['Bulgăruș', 'Neudorf']);
  assert.equal(rows[0].admin_name, 'Timiș');          // sedilă → virgulă
  assert.equal(rows[1].admin_name, 'Niederösterreich');
  assert.equal(rows[0].kind, 'village');
});

test('denumirile uzuale doar pentru localitățile mari și doar în alfabet latin', () => {
  const rows = parseGeonames(row('7', 'Wien', 'P', 'PPLC', 'AT', '09', 1900000, 'Viena,Vienna,Вена,Wien,Bécs'), new Map());
  assert.deepEqual(rows[0].alt_names, ['Viena', 'Vienna', 'Bécs']);
  const small = parseGeonames(row('8', 'Satu Mic', 'P', 'PPL', 'RO', '36', 100, 'Kisfalu'), new Map());
  assert.deepEqual(small[0].alt_names, []);
});

test('tipul localității', () => {
  assert.equal(kindOf('PPLA', 0), 'city');
  assert.equal(kindOf('PPL', 25000), 'city');
  assert.equal(kindOf('PPLA2', 900), 'town');
  assert.equal(kindOf('PPL', 3000), 'town');
  assert.equal(kindOf('PPL', 400), 'village');
});

test('codurile poștale: valide, fără dubluri, ș/ț corect', () => {
  const pc = (cc, code, name, lat = '48.1', lng = '11.5') => [cc, code, name, 'A1', '01', '', '', '', '', lat, lng, '4'].join('\t');
  const rows = parsePostcodes([
    pc('DE', '80331', 'München'),
    pc('DE', '80331', 'München'),        // dublură
    pc('RO', '307241', 'Bulgăruş'),      // sedilă
    pc('AT', '1010', 'Wien'),
    pc('DE', 'ABC', 'Fals'),             // cod invalid
    pc('FR', '75001', 'Paris'),          // altă țară
    pc('HU', '6600', 'Szentes', 'x'),    // coordonate lipsă
  ].join('\n'), ['RO', 'AT', 'DE', 'HU']);
  assert.deepEqual(rows.map((r) => `${r.country} ${r.postcode} ${r.name}`), ['DE 80331 München', 'RO 307241 Bulgăruș', 'AT 1010 Wien']);
});
