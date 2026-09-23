import type { LatLng } from '@transportos/shared';
import { haversineMeters } from './straight-line';

/**
 * Ordinea opririlor fără serviciu extern (gratuit): cel mai apropiat vecin, apoi îmbunătățire 2-opt,
 * între un start fix și un final fix (opțional). Distanțe în linie dreaptă: o estimare bună în oraș.
 */
export function localOrder(start: LatLng, end: LatLng | null, points: LatLng[]): number[] {
  const n = points.length;
  if (n <= 1) return points.map((_, i) => i);
  const left = new Set(points.map((_, i) => i));
  const order: number[] = [];
  let cur = start;
  while (left.size) {
    let best = -1; let bestD = Infinity;
    for (const i of left) { const d = haversineMeters(cur, points[i]!); if (d < bestD) { bestD = d; best = i; } }
    order.push(best); left.delete(best); cur = points[best]!;
  }
  const pathLen = (o: number[]) => {
    let s = haversineMeters(start, points[o[0]!]!);
    for (let k = 1; k < o.length; k += 1) s += haversineMeters(points[o[k - 1]!]!, points[o[k]!]!);
    return s + (end ? haversineMeters(points[o[o.length - 1]!]!, end) : 0);
  };
  let improved = true;
  let guard = 0;
  while (improved && guard < 100) {
    improved = false; guard += 1;
    for (let i = 0; i < n - 1; i += 1) {
      for (let k = i + 1; k < n; k += 1) {
        const candidate = [...order.slice(0, i), ...order.slice(i, k + 1).reverse(), ...order.slice(k + 1)];
        if (pathLen(candidate) + 1e-6 < pathLen(order)) { order.splice(0, n, ...candidate); improved = true; }
      }
    }
  }
  return order;
}
