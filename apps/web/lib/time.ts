/** Diferența (ms) dintre ora locală din fusul `timeZone` și UTC, la momentul `date`. */
function offsetMs(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(date);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return asUtc - date.getTime();
}

/**
 * Transformă o valoare din <input type="datetime-local"> („2026-09-25T18:00”),
 * interpretată ca oră locală în `timeZone`, în momentul UTC corect (inclusiv la ora de vară).
 */
export function zonedLocalToUtc(local: string, timeZone: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(local);
  if (!m) return null;
  const [, y, mo, d, h, mi] = m.map(Number) as [number, number, number, number, number, number];
  const guess = Date.UTC(y, mo - 1, d, h, mi);
  const first = offsetMs(new Date(guess), timeZone);
  let result = guess - first;
  const second = offsetMs(new Date(result), timeZone);
  if (second !== first) result = guess - second;
  return new Date(result);
}

/**
 * Adaugă zile la o oră locală („2026-10-20T18:00” + 7 → „2026-10-27T18:00”).
 * Lucrăm pe ora locală, nu pe UTC, ca plecarea să rămână la 18:00 și după
 * trecerea la ora de iarnă.
 */
export function addDaysLocal(local: string, days: number): string {
  const [datePart, timePart] = local.split('T');
  const [y, m, d] = (datePart ?? '').split('-').map(Number) as [number, number, number];
  const shifted = new Date(Date.UTC(y, m - 1, d + days));
  return `${shifted.toISOString().slice(0, 10)}T${timePart}`;
}

/** Momentul UTC afișat ca valoare pentru <input type="datetime-local">, în fusul `timeZone`. */
export function utcToZonedLocal(iso: string, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(new Date(iso));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  return `${get('year')}-${get('month')}-${get('day')}T${get('hour')}:${get('minute')}`;
}
