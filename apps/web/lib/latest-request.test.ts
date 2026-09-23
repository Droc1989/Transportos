import test from 'node:test';
import assert from 'node:assert/strict';
import { LatestRequest } from './latest-request';

test('golirea, selecția și demontarea invalidează o cerere chiar dacă răspunde după anulare', async () => {
  const requests = new LatestRequest();
  const request = requests.start();
  let resolve!: (value: string) => void;
  const response = new Promise<string>((done) => { resolve = done; });
  const committed: string[] = [];
  const pending = response.then((value) => { if (request.isCurrent()) committed.push(value); });
  requests.invalidate();
  resolve('sugestie veche');
  await pending;
  assert.equal(request.signal.aborted, true);
  assert.deepEqual(committed, []);
});
test('doar cea mai nouă cerere poate publica rezultatele', () => {
  const requests = new LatestRequest();
  const old = requests.start();
  const current = requests.start();
  assert.equal(old.isCurrent(), false);
  assert.equal(current.isCurrent(), true);
});
