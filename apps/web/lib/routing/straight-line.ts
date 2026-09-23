import type { LatLng, RouteEstimate, RouteLegs, RoutingProvider } from '@transportos/shared';

const EARTH_RADIUS_M = 6_371_000;
/** Drumul real e de obicei cu ~30% mai lung decât linia dreaptă. */
const ROAD_FACTOR = 1.3;
/** Viteză medie de microbuz pe coridor, cu autostradă și drum național. */
const AVERAGE_SPEED_KMH = 75;

export function haversineMeters(a: LatLng, b: LatLng): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

/**
 * Estimare fără server de rutare: distanța în linie dreaptă × 1,3, la 75 km/h.
 * Folosită când OSRM nu e configurat sau nu răspunde. Rezultatul e marcat „aproximativ”.
 */
export class StraightLineRoutingProvider implements RoutingProvider {
  async estimate(waypoints: LatLng[]): Promise<RouteEstimate> {
    const { legs } = await this.legs(waypoints);
    return {
      durationSeconds: legs.reduce((s, l) => s + l.durationSeconds, 0),
      distanceMeters: legs.reduce((s, l) => s + l.distanceMeters, 0),
      trafficAware: false,
    };
  }

  async legs(waypoints: LatLng[]): Promise<RouteLegs> {
    const legs = waypoints.slice(1).map((to, i) => {
      const distanceMeters = haversineMeters(waypoints[i]!, to) * ROAD_FACTOR;
      return { distanceMeters, durationSeconds: distanceMeters / ((AVERAGE_SPEED_KMH * 1000) / 3600) };
    });
    return { legs, trafficAware: false, approximate: true };
  }
}
