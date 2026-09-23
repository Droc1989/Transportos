import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mapGeoapifyPlan, mapGeoapifyRoute } from './geoapify';
import { localOrder } from './local-order';
import { applyStopPlan, buildStopPlan, type PlanStop } from './stop-plan';

test('Routing API: porțiunile de drum din răspuns', () => {
  const r = mapGeoapifyRoute({ features: [{ properties: { distance: 120000, time: 5400, legs: [
    { distance: 55000, time: 2400 }, { distance: 65000, time: 3000 }] } }] }, 3);
  assert.deepEqual(r.legs, [{ durationSeconds: 2400, distanceMeters: 55000 }, { durationSeconds: 3000, distanceMeters: 65000 }]);
  assert.equal(r.approximate, false);
  assert.throws(() => mapGeoapifyRoute({ features: [] }, 3), /incompletă/);
});

test('Route Planner: ordinea joburilor, cele neatribuite la final', () => {
  const order = mapGeoapifyPlan({ features: [{ properties: { actions: [
    { type: 'start' }, { type: 'job', job_index: 2 }, { type: 'job', job_index: 0 }, { type: 'end' }] } }] }, 3);
  assert.deepEqual(order, [2, 0, 1]);
});

test('ordinea locală: evită zigzagul', () => {
  // start la vest; punctele pe o linie spre est, date amestecat
  const start = { lat: 45.75, lng: 21.1 };
  const pts = [{ lat: 45.75, lng: 21.4 }, { lat: 45.75, lng: 21.2 }, { lat: 45.75, lng: 21.3 }];
  assert.deepEqual(localOrder(start, null, pts), [1, 2, 0]);
  assert.deepEqual(localOrder(start, { lat: 45.75, lng: 21.5 }, pts), [1, 2, 0]);
  assert.deepEqual(localOrder(start, null, [pts[0]!]), [0]);
});

const S = (id: string, kind: 'PICKUP' | 'DROPOFF', zone: number, lng: number | null, status = 'PLANNED'): PlanStop =>
  ({ id, kind, zone, status, lat: lng === null ? null : 45.75, lng });

test('planul: reordonează doar în aceeași zonă și tip', () => {
  const stops = [S('p1', 'PICKUP', 0, 21.3), S('p2', 'PICKUP', 0, 21.2), S('p3', 'PICKUP', 1, 21.35), S('d1', 'DROPOFF', 4, 16.3), S('d2', 'DROPOFF', 4, 16.4)];
  const plan = buildStopPlan(stops, { lat: 45.75, lng: 21.1 })!;
  assert.equal(plan.groups.length, 2);                       // Timișoara (2 preluări) și Wien (2 coborâri)
  const ids = applyStopPlan(plan.base, plan.groups, [[1, 0], [0, 1]]);
  assert.deepEqual(ids, ['p2', 'p1', 'p3', 'd1', 'd2']);
});

test('planul: opririle fără coordonate sau deja făcute nu se optimizează', () => {
  assert.equal(buildStopPlan([S('p1', 'PICKUP', 0, null), S('p2', 'PICKUP', 0, 21.2)], { lat: 45.75, lng: 21.1 })!.groups.length, 0);
  assert.equal(buildStopPlan([S('p1', 'PICKUP', 0, 21.3, 'DONE'), S('p2', 'PICKUP', 0, 21.2)], { lat: 45.75, lng: 21.1 })!.groups.length, 0);
  // o oprire făcută care ar trebui mutată de ordinea de bază: nu optimizăm deloc
  assert.equal(buildStopPlan([S('p3', 'PICKUP', 1, 21.3, 'DONE'), S('p1', 'PICKUP', 0, 21.2)], { lat: 45.75, lng: 21.1 }), null);
});
