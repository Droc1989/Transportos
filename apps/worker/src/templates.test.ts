import assert from 'node:assert/strict';
import { test } from 'node:test';
import { renderMessage } from './templates';

test('ETA în română, cu ora locală și linkul', () => {
  const text = renderMessage('PICKUP_ETA', 'ro',
    { company: 'Firma A', minutes: 10, eta_at: '2026-10-01T15:10:00Z' }, 'https://x/u/abc');
  assert.equal(text, 'Firma A: microbuzul ajunge la tine în aprox. 10 minute (18:10). https://x/u/abc');
});

test('germană, cu ora Vienei', () => {
  const text = renderMessage('PICKUP_ETA', 'de', { company: 'Firma A', minutes: 30, eta_at: '2026-12-01T15:30:00Z' }, null);
  assert.equal(text, 'Firma A: Der Kleinbus ist in ca. 30 Minuten bei dir (16:30).');
});

test('limbă necunoscută → română', () => {
  assert.match(renderMessage('TRIP_CANCELLED', 'fr', { company: 'F', trip_title: 'T' }, null), /a fost anulată/);
});

test('șablon necunoscut → eroare', () => {
  assert.throws(() => renderMessage('NOPE', 'ro', {}, null));
});
