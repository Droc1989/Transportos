// Adaptoare pentru furnizori externi (master plan §9). Aplicația depinde doar de
// aceste interfețe; implementările concrete (OSRM, Google, Stripe…) se pot schimba.

export interface LatLng {
  lat: number;
  lng: number;
}

export interface RouteEstimate {
  durationSeconds: number;
  distanceMeters: number;
  /** true dacă estimarea ține cont de traficul live (ex. Google Routes). */
  trafficAware: boolean;
}

export interface RouteLeg {
  durationSeconds: number;
  distanceMeters: number;
}

export interface RouteLegs {
  /** O porțiune pentru fiecare pereche de puncte consecutive (n puncte → n-1 porțiuni). */
  legs: RouteLeg[];
  trafficAware: boolean;
  /** true dacă e o estimare aproximativă (ex. linie dreaptă), nu o rută reală pe drum. */
  approximate: boolean;
}

/** Calcul de rute și ETA. Implicit OSRM propriu; Google Routes doar aproape de preluare. */
export interface RoutingProvider {
  estimate(waypoints: LatLng[]): Promise<RouteEstimate>;
  legs(waypoints: LatLng[]): Promise<RouteLegs>;
}

export interface GeocodeResult {
  label: string;
  location: LatLng;
  postalCode?: string;
  countryCode?: string;
}

/** Autocompletare și geocodare de adrese. */
export interface GeocodingProvider {
  search(query: string, opts?: { language?: 'ro' | 'de' | 'en'; countries?: string[] }): Promise<GeocodeResult[]>;
}

export type NotificationChannel = 'PUSH' | 'SMS' | 'WHATSAPP' | 'EMAIL';

export interface NotificationMessage {
  to: string;
  channel: NotificationChannel;
  templateKey: string;
  params: Record<string, string>;
  locale: 'ro' | 'de' | 'en';
}

export interface NotificationProvider {
  send(message: NotificationMessage): Promise<{ providerMessageId: string }>;
}
