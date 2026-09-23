import type { RouteLeg, StopKind } from '@transportos/shared';

/** Minute de oprire: la urcare se încarcă bagaje, la coborâre se descarcă. */
export const DWELL_MINUTES: Record<StopKind, number> = { PICKUP: 5, DROPOFF: 3 };

/**
 * Orele planificate ale opririlor.
 * `legs[0]` = de la plecare la prima oprire, `legs[i]` = de la oprirea i-1 la oprirea i.
 * Ora opririi i = ora sosirii acolo; timpul de oprire se adaugă după.
 */
export function computeSchedule(departure: Date, legs: RouteLeg[], kinds: StopKind[]): Date[] {
  if (legs.length !== kinds.length) {
    throw new Error(`Număr greșit de porțiuni: ${legs.length} pentru ${kinds.length} opriri`);
  }
  const times: Date[] = [];
  let t = departure.getTime();
  kinds.forEach((kind, i) => {
    t += legs[i]!.durationSeconds * 1000;
    times.push(new Date(t));
    t += DWELL_MINUTES[kind] * 60 * 1000;
  });
  return times;
}
