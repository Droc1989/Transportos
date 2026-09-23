import type { GeocodeOptions, GeocodeResult, GeocodingProvider } from '@transportos/shared';

// Adrese (străzi și numere) prin servicii externe. Doar pe server: cheile nu ajung în browser.
// Implicit Geoapify (plan gratuit, date OpenStreetMap); când volumul crește, Photon propriu
// (PHOTON_URL), fără plată per căutare. Fără niciuna configurată: adresa rămâne text liber.

const COUNTRIES = ['ro', 'at', 'de', 'hu'];

type GeoapifyResult = {
  formatted?: string; address_line1?: string; address_line2?: string; street?: string; housenumber?: string;
  postcode?: string; city?: string; village?: string; town?: string; country_code?: string; lat: number; lon: number;
};

export function mapGeoapify(json: { results?: GeoapifyResult[] }): GeocodeResult[] {
  return (json.results ?? [])
    .filter((r) => COUNTRIES.includes((r.country_code ?? '').toLowerCase()) && Number.isFinite(r.lat) && Number.isFinite(r.lon))
    .map((r) => ({
      label: r.formatted ?? [r.address_line1, r.address_line2].filter(Boolean).join(', '),
      location: { lat: r.lat, lng: r.lon },
      postalCode: r.postcode,
      countryCode: r.country_code?.toUpperCase(),
      street: r.street,
      houseNumber: r.housenumber,
      city: r.city ?? r.town ?? r.village,
    }));
}

type PhotonFeature = {
  geometry: { coordinates: [number, number] };
  properties: { name?: string; street?: string; housenumber?: string; postcode?: string; city?: string; countrycode?: string };
};

export function mapPhoton(json: { features?: PhotonFeature[] }): GeocodeResult[] {
  return (json.features ?? [])
    .filter((f) => COUNTRIES.includes((f.properties.countrycode ?? '').toLowerCase()))
    .map((f) => {
      const p = f.properties;
      const streetLine = [p.street ?? p.name, p.housenumber].filter(Boolean).join(' ');
      const cityLine = [p.postcode, p.city].filter(Boolean).join(' ');
      return {
        label: [streetLine, cityLine].filter(Boolean).join(', '),
        location: { lat: f.geometry.coordinates[1], lng: f.geometry.coordinates[0] },
        postalCode: p.postcode,
        countryCode: p.countrycode?.toUpperCase(),
        street: p.street ?? p.name,
        houseNumber: p.housenumber,
        city: p.city,
      };
    });
}

export class GeoapifyProvider implements GeocodingProvider {
  readonly name = 'geoapify';
  readonly attribution = 'Powered by Geoapify · © OpenStreetMap contributors';
  constructor(private readonly apiKey: string, private readonly baseUrl = 'https://api.geoapify.com') {}

  async search(query: string, opts: GeocodeOptions = {}): Promise<GeocodeResult[]> {
    const params = new URLSearchParams({
      text: query, format: 'json', limit: String(opts.limit ?? 5), lang: opts.language ?? 'ro',
      filter: `countrycode:${(opts.countries ?? COUNTRIES).map((c) => c.toLowerCase()).join(',')}`,
      apiKey: this.apiKey,
    });
    if (opts.near) params.set('bias', `proximity:${opts.near.lng},${opts.near.lat}`);
    const res = await fetch(`${this.baseUrl}/v1/geocode/autocomplete?${params}`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) throw new Error(`geoapify ${res.status}`);
    return mapGeoapify(await res.json());
  }
}

export class PhotonProvider implements GeocodingProvider {
  readonly name = 'photon';
  readonly attribution = '© OpenStreetMap contributors';
  constructor(private readonly baseUrl: string) {}

  async search(query: string, opts: GeocodeOptions = {}): Promise<GeocodeResult[]> {
    const params = new URLSearchParams({ q: query, limit: String((opts.limit ?? 5) * 2) });
    if (opts.near) { params.set('lat', String(opts.near.lat)); params.set('lon', String(opts.near.lng)); }
    if (opts.language === 'de') params.set('lang', 'de');
    const res = await fetch(`${this.baseUrl.replace(/\/$/, '')}/api?${params}`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) throw new Error(`photon ${res.status}`);
    return mapPhoton(await res.json()).slice(0, opts.limit ?? 5);
  }
}

export function getGeocoder(): GeocodingProvider | null {
  if (process.env.PHOTON_URL) return new PhotonProvider(process.env.PHOTON_URL);
  if (process.env.GEOAPIFY_API_KEY) return new GeoapifyProvider(process.env.GEOAPIFY_API_KEY, process.env.GEOAPIFY_BASE_URL);
  return null;
}

/** Memorie scurtă pentru rezultate: aceeași căutare nu consumă din nou din cota serviciului. */
export class TtlCache<T> {
  private map = new Map<string, { value: T; at: number }>();
  constructor(private readonly max = 500, private readonly ttlMs = 10 * 60 * 1000) {}
  get(key: string, now = Date.now()): T | undefined {
    const hit = this.map.get(key);
    if (!hit) return undefined;
    if (now - hit.at > this.ttlMs) { this.map.delete(key); return undefined; }
    this.map.delete(key); this.map.set(key, hit); // cel mai recent folosit la final
    return hit.value;
  }
  set(key: string, value: T, now = Date.now()): void {
    if (this.map.has(key)) this.map.delete(key);
    this.map.set(key, { value, at: now });
    while (this.map.size > this.max) this.map.delete(this.map.keys().next().value!);
  }
}

/** Limită simplă pe minut, per adresă IP, ca să nu se consume cota gratuită din abuz. */
export class RateLimiter {
  private hits = new Map<string, number[]>();
  constructor(private readonly perMinute = 40) {}
  allow(key: string, now = Date.now()): boolean {
    const recent = (this.hits.get(key) ?? []).filter((t) => now - t < 60_000);
    if (recent.length >= this.perMinute) { this.hits.set(key, recent); return false; }
    recent.push(now); this.hits.set(key, recent);
    if (this.hits.size > 5000) this.hits.clear();
    return true;
  }
}
