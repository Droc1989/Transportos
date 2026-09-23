import type { LatLng, RouteLegs } from '@transportos/shared';
import { TtlCache } from '@/lib/geocoding/providers';
import { GeoapifyRoutingProvider } from './geoapify';
import { localOrder } from './local-order';
import { OsrmRoutingProvider } from './osrm';
import { StraightLineRoutingProvider } from './straight-line';

// Rezultatele pe drum real se păstrează o zi: recalcularea aceleiași curse nu consumă din nou credite.
const legsCache = new TtlCache<RouteLegs>(300, 24 * 60 * 60 * 1000);
const key = (w: LatLng[]) => w.map((p) => `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`).join('|');

function geoapify(): GeoapifyRoutingProvider | null {
  const k = process.env.GEOAPIFY_API_KEY;
  return k ? new GeoapifyRoutingProvider(k, process.env.GEOAPIFY_BASE_URL) : null;
}

/**
 * Durata porțiunilor dintre puncte, pe drum real: OSRM propriu (OSRM_URL) dacă există, altfel
 * Geoapify (GEOAPIFY_API_KEY); dacă niciunul nu e configurat sau nu răspunde, estimarea în linie
 * dreaptă, marcată ca aproximativă.
 */
export async function routeLegs(waypoints: LatLng[]): Promise<RouteLegs> {
  const cached = legsCache.get(key(waypoints));
  if (cached) return cached;
  const osrmUrl = process.env.OSRM_URL;
  if (osrmUrl) {
    try {
      const r = await new OsrmRoutingProvider(osrmUrl).legs(waypoints);
      legsCache.set(key(waypoints), r);
      return r;
    } catch (error) {
      console.warn('OSRM indisponibil:', (error as Error).message);
    }
  }
  const g = geoapify();
  if (g) {
    try {
      const r = await g.legs(waypoints);
      legsCache.set(key(waypoints), r);
      return r;
    } catch (error) {
      console.warn('Geoapify routing indisponibil, folosesc estimarea aproximativă:', (error as Error).message);
    }
  }
  return new StraightLineRoutingProvider().legs(waypoints);
}

/**
 * Ordinea optimă a unor opriri între un start și un final: Geoapify Route Planner (drum real) dacă e
 * configurat și răspunde, altfel metoda locală gratuită (linie dreaptă).
 */
export async function planOrder(start: LatLng, end: LatLng | null, points: LatLng[]): Promise<{ order: number[]; source: 'geoapify' | 'local' }> {
  if (points.length <= 1) return { order: points.map((_, i) => i), source: 'local' };
  const g = geoapify();
  if (g) {
    try {
      return { order: await g.planOrder(start, end, points), source: 'geoapify' };
    } catch (error) {
      console.warn('Geoapify Route Planner indisponibil, folosesc ordinea locală:', (error as Error).message);
    }
  }
  return { order: localOrder(start, end, points), source: 'local' };
}
