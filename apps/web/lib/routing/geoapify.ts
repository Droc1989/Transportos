import type { LatLng, RouteEstimate, RouteLegs, RoutingProvider } from '@transportos/shared';

// Geoapify: Routing API (durata pe drum real între opriri) și Route Planner API (ordinea optimă a
// opririlor). Aceeași cheie ca la adrese (GEOAPIFY_API_KEY), aceeași cotă gratuită. Doar pe server.

type RoutingResponse = { features?: { properties: { distance: number; time: number; legs?: { distance: number; time: number }[] } }[] };

export function mapGeoapifyRoute(json: RoutingResponse, waypointCount: number): RouteLegs {
  const props = json.features?.[0]?.properties;
  if (!props?.legs || props.legs.length !== waypointCount - 1) throw new Error('geoapify: rută incompletă');
  return {
    legs: props.legs.map((l) => ({ durationSeconds: l.time, distanceMeters: l.distance })),
    trafficAware: false,
    approximate: false,
  };
}

type PlannerResponse = { features?: { properties: { actions?: { type: string; job_index?: number }[] } }[] };

/** Ordinea joburilor din răspunsul Route Planner; joburile neatribuite rămân la final, în ordinea inițială. */
export function mapGeoapifyPlan(json: PlannerResponse, jobCount: number): number[] {
  const order: number[] = [];
  for (const f of json.features ?? []) {
    for (const a of f.properties.actions ?? []) {
      if (a.type === 'job' && typeof a.job_index === 'number' && a.job_index < jobCount && !order.includes(a.job_index)) {
        order.push(a.job_index);
      }
    }
  }
  for (let i = 0; i < jobCount; i += 1) if (!order.includes(i)) order.push(i);
  return order;
}

export class GeoapifyRoutingProvider implements RoutingProvider {
  constructor(private readonly apiKey: string, private readonly baseUrl = 'https://api.geoapify.com') {}

  async legs(waypoints: LatLng[]): Promise<RouteLegs> {
    if (waypoints.length < 2) throw new Error('Sunt necesare cel puțin două puncte.');
    const params = new URLSearchParams({
      waypoints: waypoints.map((p) => `${p.lat},${p.lng}`).join('|'), mode: 'drive', apiKey: this.apiKey,
    });
    const res = await fetch(`${this.baseUrl}/v1/routing?${params}`, { cache: 'no-store', signal: AbortSignal.timeout(10000) });
    if (!res.ok) throw new Error(`geoapify routing ${res.status}`);
    return mapGeoapifyRoute(await res.json(), waypoints.length);
  }

  async estimate(waypoints: LatLng[]): Promise<RouteEstimate> {
    const { legs } = await this.legs(waypoints);
    return {
      durationSeconds: legs.reduce((s, l) => s + l.durationSeconds, 0),
      distanceMeters: legs.reduce((s, l) => s + l.distanceMeters, 0),
      trafficAware: false,
    };
  }

  /** Ordinea optimă a punctelor între un start și (opțional) un final fix. */
  async planOrder(start: LatLng, end: LatLng | null, points: LatLng[]): Promise<number[]> {
    const body = {
      mode: 'drive',
      agents: [{ start_location: [start.lng, start.lat], ...(end ? { end_location: [end.lng, end.lat] } : {}) }],
      jobs: points.map((p) => ({ location: [p.lng, p.lat], duration: 120 })),
    };
    const res = await fetch(`${this.baseUrl}/v1/routeplanner?apiKey=${encodeURIComponent(this.apiKey)}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      cache: 'no-store', signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) throw new Error(`geoapify routeplanner ${res.status}`);
    return mapGeoapifyPlan(await res.json(), points.length);
  }
}
