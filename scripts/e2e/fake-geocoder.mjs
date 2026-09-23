// Geoapify fals pentru testele cap-coadă: răspunde la /v1/geocode/autocomplete în formatul real
// și numără cererile (GET /__requests), ca să verificăm că rezultatele se refolosesc. DOAR PENTRU TESTE.
import http from 'node:http';

const port = Number(process.env.PORT ?? 12112);
const ADDRESSES = [
  { formatted: 'Strada Principală 7, 307241 Bulgăruș, România', street: 'Strada Principală', housenumber: '7', postcode: '307241', village: 'Bulgăruș', country_code: 'ro', lat: 45.915, lon: 21.074 },
  { formatted: 'Piața Unirii 1, 300085 Timișoara, România', street: 'Piața Unirii', housenumber: '1', postcode: '300085', city: 'Timișoara', country_code: 'ro', lat: 45.758, lon: 21.229 },
  { formatted: 'Piața Victoriei 2, 300030 Timișoara, România', street: 'Piața Victoriei', housenumber: '2', postcode: '300030', city: 'Timișoara', country_code: 'ro', lat: 45.7537, lon: 21.2257 },
  { formatted: 'Marienplatz 1, 80331 München, Deutschland', street: 'Marienplatz', housenumber: '1', postcode: '80331', city: 'München', country_code: 'de', lat: 48.137, lon: 11.575 },
  { formatted: 'Stephansplatz 1, 1010 Wien, Österreich', street: 'Stephansplatz', housenumber: '1', postcode: '1010', city: 'Wien', country_code: 'at', lat: 48.2085, lon: 16.373 },
  { formatted: 'Rue de Rivoli 1, 75001 Paris, France', country_code: 'fr', lat: 48.86, lon: 2.35 },
];
const norm = (s) => s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
let requests = 0;

http.createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  const json = (status, obj) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
  if (url.pathname === '/__requests') return json(200, { requests });
  if (url.pathname !== '/v1/geocode/autocomplete') return json(404, {});
  if (!url.searchParams.get('apiKey')) return json(401, { message: 'no key' });
  requests += 1;
  const text = norm(url.searchParams.get('text') ?? '');
  const bias = /proximity:([-\d.]+),([-\d.]+)/.exec(url.searchParams.get('bias') ?? '');
  let results = ADDRESSES.filter((a) => norm(a.formatted).includes(text));
  if (bias) {
    const [lng, lat] = [Number(bias[1]), Number(bias[2])];
    results = results.sort((a, b) => Math.hypot(a.lat - lat, a.lon - lng) - Math.hypot(b.lat - lat, b.lon - lng));
  }
  return json(200, { results: results.slice(0, Number(url.searchParams.get('limit') ?? 5)) });
}).listen(port, () => console.log(`fake geocoder :${port}`));
