import type { LatLng, RouteEstimate, RouteLegs, RoutingProvider } from '@transportos/shared';

type OsrmResponse = {
  code: string;
  routes?: { duration: number; distance: number; legs: { duration: number; distance: number }[] }[];
};

/**
 * RoutingProvider pe un server OSRM propriu (fără cost pe apel, fără trafic live).
 * Pentru ETA cu trafic în ultimele ~45 de minute înainte de preluare se adaugă
 * un GoogleRoutesProvider cu aceeași interfață (docs/adr/0003-harti-si-rutare.md).
 */
export class OsrmRoutingProvider implements RoutingProvider {
  constructor(private readonly baseUrl: string) {}

  private async route(waypoints: LatLng[]) {
    if (waypoints.length < 2) throw new Error('Sunt necesare cel puțin două puncte.');
    const coords = waypoints.map((p) => `${p.lng},${p.lat}`).join(';');
    const res = await fetch(`${this.baseUrl}/route/v1/driving/${coords}?overview=false`, {
      cache: 'no-store',
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`OSRM a răspuns cu ${res.status}`);
    const body = (await res.json()) as OsrmResponse;
    const route = body.routes?.[0];
    if (body.code !== 'Ok' || !route) throw new Error(`OSRM: ${body.code}`);
    return route;
  }

  async estimate(waypoints: LatLng[]): Promise<RouteEstimate> {
    const route = await this.route(waypoints);
    return { durationSeconds: route.duration, distanceMeters: route.distance, trafficAware: false };
  }

  async legs(waypoints: LatLng[]): Promise<RouteLegs> {
    const route = await this.route(waypoints);
    return {
      legs: route.legs.map((l) => ({ durationSeconds: l.duration, distanceMeters: l.distance })),
      trafficAware: false,
      approximate: false,
    };
  }
}
