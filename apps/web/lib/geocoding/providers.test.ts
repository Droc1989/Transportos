import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mapGeoapify, mapPhoton, RateLimiter, TtlCache } from './providers';

test('Geoapify: adresele din cele 4 țări, cu coordonate', () => {
  const r = mapGeoapify({ results: [
    { formatted: 'Strada Principală 7, 307241 Bulgăruș, România', street: 'Strada Principală', housenumber: '7', postcode: '307241',
      village: 'Bulgăruș', country_code: 'ro', lat: 45.915, lon: 21.074 },
    { formatted: 'Rue de Rivoli 1, Paris', country_code: 'fr', lat: 48.86, lon: 2.35 },
  ] });
  assert.equal(r.length, 1);
  assert.equal(r[0]!.label, 'Strada Principală 7, 307241 Bulgăruș, România');
  assert.deepEqual(r[0]!.location, { lat: 45.915, lng: 21.074 });
  assert.equal(r[0]!.city, 'Bulgăruș');
  assert.equal(r[0]!.countryCode, 'RO');
});

test('Photon: eticheta din stradă, număr, cod și oraș', () => {
  const r = mapPhoton({ features: [
    { geometry: { coordinates: [11.575, 48.137] }, properties: { street: 'Marienplatz', housenumber: '1', postcode: '80331', city: 'München', countrycode: 'DE' } },
    { geometry: { coordinates: [2.35, 48.86] }, properties: { name: 'Louvre', city: 'Paris', countrycode: 'FR' } },
  ] });
  assert.deepEqual(r.map((x) => x.label), ['Marienplatz 1, 80331 München']);
  assert.deepEqual(r[0]!.location, { lat: 48.137, lng: 11.575 });
});

test('memoria scurtă: păstrează, expiră și nu crește la nesfârșit', () => {
  const c = new TtlCache<number>(2, 1000);
  c.set('a', 1, 0); c.set('b', 2, 0);
  assert.equal(c.get('a', 500), 1);
  c.set('c', 3, 600);                 // scoate cel mai vechi folosit („b”)
  assert.equal(c.get('b', 600), undefined);
  assert.equal(c.get('a', 2000), undefined); // expirat
});

test('limita pe minut', () => {
  const l = new RateLimiter(3);
  assert.equal([1, 2, 3, 4].map(() => l.allow('ip', 1000)).join(), 'true,true,true,false');
  assert.equal(l.allow('ip', 70_000), true);   // după un minut, din nou
  assert.equal(l.allow('alt-ip', 1000), true);
});
