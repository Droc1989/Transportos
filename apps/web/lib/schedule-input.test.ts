import test from 'node:test';
import assert from 'node:assert/strict';
import { scheduleCoordinatesReady } from './schedule-input';
const p = { lat: 45, lng: 21 };
test('o oprire intermediară fără coordonate blochează întregul calcul', () => {
  assert.equal(scheduleCoordinatesReady(p, [p, { lat: null, lng: null }, p]), false);
});
test('traseul gol, plecarea lipsă și coordonatele invalide nu sunt succes', () => {
  assert.equal(scheduleCoordinatesReady(p, []), false);
  assert.equal(scheduleCoordinatesReady(undefined, [p]), false);
  assert.equal(scheduleCoordinatesReady(p, [{ lat: NaN, lng: 21 }]), false);
  assert.equal(scheduleCoordinatesReady(p, [{ lat: 91, lng: 21 }]), false);
});
test('toate opririle localizate permit calculul inclusiv coordonata zero', () => {
  assert.equal(scheduleCoordinatesReady(p, [p, { lat: 0, lng: 0 }]), true);
});
