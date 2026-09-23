import assert from 'node:assert/strict';
import { test } from 'node:test';
import { matchPlace } from './place-match';

const names = ['Timișoara', 'Arad', 'Cluj-Napoca', 'București', 'Wien', 'St. Pölten', 'Linz', 'München', 'Nürnberg',
  'Frankfurt am Main', 'Köln', 'Salzburg', 'Szeged', 'Győr', 'Graz'];
const places = names.map((name, i) => ({ id: `00000000-0000-0000-0000-0000000000${String(i).padStart(2, '0')}`, name }));
const find = (q: string) => matchPlace(q, places)?.name ?? null;

test('numele exact și fără diacritice', () => {
  assert.equal(find('Timișoara'), 'Timișoara');
  assert.equal(find('timisoara'), 'Timișoara');
  assert.equal(find('  BUCURESTI '), 'București');
  assert.equal(find('Gyor'), 'Győr');
});

test('transliterări germane', () => {
  assert.equal(find('Muenchen'), 'München');
  assert.equal(find('Munchen'), 'München');
  assert.equal(find('Nuernberg'), 'Nürnberg');
  assert.equal(find('Koeln'), 'Köln');
});

test('denumiri uzuale în română și engleză', () => {
  assert.equal(find('Viena'), 'Wien');
  assert.equal(find('Vienna'), 'Wien');
  assert.equal(find('Munich'), 'München');
  assert.equal(find('Colonia'), 'Köln');
  assert.equal(find('Sankt Pölten'), 'St. Pölten');
  assert.equal(find('St Polten'), 'St. Pölten');
});

test('începutul unic al numelui', () => {
  assert.equal(find('Cluj'), 'Cluj-Napoca');
  assert.equal(find('Frankfurt'), 'Frankfurt am Main');
  assert.equal(find('Salz'), 'Salzburg');
});

test('ambiguu sau necunoscut: nimic (nu ghicim)', () => {
  assert.equal(find('Sz'), null);          // prea scurt
  assert.equal(find('Gr'), null);          // prea scurt
  assert.equal(find('Paris'), null);
  assert.equal(find(''), null);
  assert.equal(matchPlace('Li', [...places, { id: 'x', name: 'Lienz' }]), null); // prea scurt
  assert.equal(matchPlace('Lin', [...places, { id: 'x', name: 'Lindau' }]), null); // două orașe încep la fel
});

test('identificatorul intern', () => {
  assert.equal(matchPlace(places[4]!.id, places)?.name, 'Wien');
});
