type Point = { lat: number | null; lng: number | null };
const validPoint = (p: Point | null | undefined): boolean => !!p &&
  typeof p.lat === 'number' && Number.isFinite(p.lat) && p.lat >= -90 && p.lat <= 90 &&
  typeof p.lng === 'number' && Number.isFinite(p.lng) && p.lng >= -180 && p.lng <= 180;

/** Nu calculăm ore pe un traseu din care am eliminat opriri nelocalizate. */
export function scheduleCoordinatesReady(start: Point | null | undefined, stops: Point[]): boolean {
  return validPoint(start) && stops.length > 0 && stops.every(validPoint);
}
