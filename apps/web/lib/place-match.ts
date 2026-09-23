/**
 * Găsește orașul scris de vizitator în lista de orașe a platformei.
 * Acceptă: identificatorul intern, numele fără diacritice („Timisoara”), transliterări germane
 * („Muenchen”, „Nuernberg”), denumirile uzuale în română/engleză („Viena”, „Munich”) și începutul
 * unic al unui nume („Cluj” → „Cluj-Napoca”, „Frankfurt” → „Frankfurt am Main”).
 * Întoarce null dacă nu găsește sau dacă textul se potrivește cu mai multe orașe.
 */
export type MatchablePlace = { id: string; name: string };

export function normalizePlace(value: string): string {
  return value
    .toLowerCase()
    .replace(/ß/g, 'ss')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ae/g, 'a')
    .replace(/oe/g, 'o')
    .replace(/ue/g, 'u')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

// Denumiri uzuale → numele din baza de date (cheile sunt deja normalizate).
const ALIASES: Record<string, string> = {
  viena: 'Wien',
  vienna: 'Wien',
  munich: 'München',
  'monaco di baviera': 'München',
  nuremberg: 'Nürnberg',
  cologne: 'Köln',
  colonia: 'Köln',
  bucharest: 'București',
  'sankt polten': 'St. Pölten',
  'st polten': 'St. Pölten',
};

export function matchPlace<T extends MatchablePlace>(input: string | undefined | null, places: T[]): T | null {
  const raw = (input ?? '').trim();
  if (!raw) return null;
  const byId = places.find((p) => p.id === raw);
  if (byId) return byId;

  const q = normalizePlace(raw);
  if (!q) return null;
  const exact = places.find((p) => normalizePlace(p.name) === q);
  if (exact) return exact;

  const alias = ALIASES[q];
  if (alias) {
    const target = places.find((p) => p.name === alias);
    if (target) return target;
  }

  // Începutul unic al unui nume: „cluj” → „cluj napoca”, „frankfurt” → „frankfurt am main”.
  if (q.length >= 3) {
    const starts = places.filter((p) => normalizePlace(p.name).startsWith(q));
    if (starts.length === 1) return starts[0]!;
  }
  return null;
}
