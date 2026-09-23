import type { LatLng } from '@transportos/shared';

export type PlanStop = {
  id: string; kind: 'PICKUP' | 'DROPOFF'; status: string; lat: number | null; lng: number | null;
  /** oprirea rutei: pentru urcare from_seq, pentru coborâre to_seq */
  zone: number;
};

export type PlanGroup = { index: number[]; start: LatLng; end: LatLng | null; points: LatLng[] };

const kindRank = (k: PlanStop['kind']) => (k === 'DROPOFF' ? 0 : 1);
const pos = (s: PlanStop): LatLng | null => (s.lat !== null && s.lng !== null ? { lat: s.lat, lng: s.lng } : null);

/**
 * Pregătește optimizarea: ordonează opririle pe zone (oprirea rutei, apoi coborâri înaintea urcărilor),
 * fără să mute opririle deja făcute, și găsește grupurile care se pot reordona (aceeași zonă și tip,
 * cel puțin 2 opriri cu coordonate, încă neefectuate). Întoarce null dacă ordinea de bază ar muta o
 * oprire deja făcută (atunci nu optimizăm).
 */
export function buildStopPlan(stops: PlanStop[], tripStart: LatLng): { base: PlanStop[]; groups: PlanGroup[] } | null {
  const base = [...stops].sort((a, b) => a.zone - b.zone || kindRank(a.kind) - kindRank(b.kind));
  if (base.some((s, i) => s.status !== 'PLANNED' && stops[i]?.id !== s.id)) return null;
  const groups: PlanGroup[] = [];
  let i = 0;
  while (i < base.length) {
    let j = i;
    while (j + 1 < base.length && base[j + 1]!.zone === base[i]!.zone && base[j + 1]!.kind === base[i]!.kind) j += 1;
    const members: number[] = [];
    for (let k = i; k <= j; k += 1) if (base[k]!.status === 'PLANNED' && pos(base[k]!)) members.push(k);
    if (members.length >= 2 && members.length === j - i + 1) {
      const before = [...base.slice(0, i)].reverse().map(pos).find(Boolean) ?? tripStart;
      const after = base.slice(j + 1).map(pos).find(Boolean) ?? null;
      groups.push({ index: members, start: before, end: after, points: members.map((k) => pos(base[k]!)!) });
    }
    i = j + 1;
  }
  return { base, groups };
}

/** Aplică ordinile găsite pentru fiecare grup și întoarce lista finală de identificatori. */
export function applyStopPlan(base: PlanStop[], groups: PlanGroup[], orders: number[][]): string[] {
  const result = base.map((s) => s.id);
  groups.forEach((g, gi) => {
    const order = orders[gi]!;
    g.index.forEach((slot, k) => { result[slot] = base[g.index[order[k]!]!]!.id; });
  });
  return result;
}
