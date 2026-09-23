import type { SupabaseClient } from '@supabase/supabase-js';

export type ResolvedPlace = {
  id: string; name: string; admin_name: string | null; country: string; lat: number; lng: number;
};
type Row = ResolvedPlace & {
  match?: 'exact' | 'alias' | 'prefix' | 'similar' | 'postcode' | 'postcode_prefix'; kind?: string; postcode?: string | null;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CORE_KIND = 'city';

/**
 * Transformă ce a trimis vizitatorul (identificator ales din sugestii sau text scris) într-o localitate.
 * - identificator: localitatea respectivă;
 * - text cu o singură potrivire sigură (nume exact, denumire uzuală sau cod poștal complet): acea localitate;
 *   dacă printre potrivirile sigure e un singur oraș, îl alegem (de ex. „Arad” orașul, nu satul);
 * - altfel: variantele, ca vizitatorul să aleagă (sate cu același nume, nume scrise diferit).
 */
export async function resolvePlace(
  client: SupabaseClient, value: string | undefined,
): Promise<{ place: ResolvedPlace | null; candidates: ResolvedPlace[] }> {
  const raw = (value ?? '').trim();
  if (!raw) return { place: null, candidates: [] };
  if (UUID.test(raw)) {
    const { data } = await client.rpc('get_places', { p_ids: [raw] });
    return { place: ((data ?? []) as ResolvedPlace[])[0] ?? null, candidates: [] };
  }
  const { data, error } = await client.rpc('search_places', { p_query: raw.split(',')[0], p_country: null, p_limit: 6 });
  if (error) throw error;
  const rows = (data ?? []) as Row[];
  // Potriviri sigure: numele exact, denumirea uzuală sau codul poștal complet („80331”).
  const strong = rows.filter((r) => r.match === 'exact' || r.match === 'alias' || r.match === 'postcode');
  if (strong.length === 1) return { place: strong[0]!, candidates: [] };
  if (strong.length > 1) {
    // Textul poate conține și județul/regiunea („Satu Nou, Timiș”): îl folosim ca să alegem.
    const hint = raw.includes(',') ? raw.split(',').slice(1).join(',').trim().toLowerCase() : '';
    const byHint = hint ? strong.filter((r) => (r.admin_name ?? '').toLowerCase() === hint) : [];
    if (byHint.length === 1) return { place: byHint[0]!, candidates: [] };
    const cities = strong.filter((r) => r.kind === CORE_KIND);
    if (cities.length === 1) return { place: cities[0]!, candidates: [] };
    return { place: null, candidates: strong };
  }
  if (rows.length === 1) return { place: rows[0]!, candidates: [] };
  return { place: null, candidates: rows };
}
