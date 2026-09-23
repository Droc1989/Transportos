import test from 'node:test';
import assert from 'node:assert/strict';
import { addressBudget } from './budget';

test('limita comună permite doar confirmarea explicită a bazei', async () => {
  assert.equal(await addressBudget(async () => ({ data: true, error: null })), 'allowed');
  assert.equal(await addressBudget(async () => ({ data: false, error: null })), 'limited');
});
test('migrația lipsă, configurația lipsă sau baza indisponibilă nu consumă API-ul extern', async () => {
  assert.equal(await addressBudget(async () => ({ data: null, error: { code: 'PGRST202' } })), 'unavailable');
  assert.equal(await addressBudget(async () => { throw new Error('offline'); }), 'unavailable');
  assert.equal(await addressBudget(async () => ({ data: null, error: null })), 'unavailable');
});
