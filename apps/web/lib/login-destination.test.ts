import test from 'node:test';
import assert from 'node:assert/strict';
import { loginDestination } from './login-destination';

test('login fără next trece prin pagina care alege destinația după rol', () => {
  for (const next of [undefined, null, '']) assert.equal(loginDestination(next), '/');
});
test('login păstrează destinația internă și parametrii rezervării', () => {
  assert.equal(loginDestination('/rezerva/trip?from=1&to=3'), '/rezerva/trip?from=1&to=3');
  assert.equal(loginDestination('/admin'), '/admin');
});
test('login refuză destinații externe și separatori ambigui', () => {
  for (const next of ['https://example.invalid', '//example.invalid', '/\\example.invalid', '/\n/example.invalid']) {
    assert.equal(loginDestination(next), '/');
  }
});
