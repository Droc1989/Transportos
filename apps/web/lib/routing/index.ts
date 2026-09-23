import type { LatLng, RouteLegs } from '@transportos/shared';
import { OsrmRoutingProvider } from './osrm';
import { StraightLineRoutingProvider } from './straight-line';

/**
 * Durata porțiunilor dintre puncte. Folosește OSRM dacă OSRM_URL e setat și răspunde;
 * altfel cade pe estimarea în linie dreaptă, marcată ca aproximativă.
 */
export async function routeLegs(waypoints: LatLng[]): Promise<RouteLegs> {
  const osrmUrl = process.env.OSRM_URL;
  if (osrmUrl) {
    try {
      return await new OsrmRoutingProvider(osrmUrl).legs(waypoints);
    } catch (error) {
      console.warn('OSRM indisponibil, folosesc estimarea aproximativă:', (error as Error).message);
    }
  }
  return new StraightLineRoutingProvider().legs(waypoints);
}
