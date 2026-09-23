import { NextResponse, type NextRequest } from 'next/server';
import type { LatLng } from '@transportos/shared';
import { getGeocoder, TtlCache } from '@/lib/geocoding/providers';
import { addressBudget } from '@/lib/geocoding/budget';
import { createServiceClient } from '@/lib/supabase/service';
import { createAnonClient } from '@/lib/supabase/anon';

// Sugestii publice de adrese; apelurile externe consumă un buget comun numai pe server.
// Răspunsurile se păstrează 10 minute și sunt limitate pe minut, ca să nu se consume cota gratuită.
const results = new TtlCache<{ label: string; lat: number; lng: number; postcode: string | null }[]>(1000);
const nearCache = new TtlCache<LatLng | null>(500, 60 * 60 * 1000);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function resolveNear(near: string): Promise<LatLng | null> {
  const cached = nearCache.get(near);
  if (cached !== undefined) return cached;
  const anon = createAnonClient();
  const { data } = UUID.test(near)
    ? await anon.rpc('get_places', { p_ids: [near] })
    : await anon.rpc('search_places', { p_query: near.split(',')[0], p_country: null, p_limit: 1 });
  const row = ((data ?? []) as { lat: number; lng: number }[])[0];
  const value = row ? { lat: row.lat, lng: row.lng } : null;
  nearCache.set(near, value);
  return value;
}

export async function GET(request: NextRequest) {
  const geocoder = getGeocoder();
  if (!geocoder) return NextResponse.json({ items: [], attribution: null, provider: null });

  const sp = request.nextUrl.searchParams;
  const q = (sp.get('q') ?? '').trim().slice(0, 120);
  if (q.length < 3) return NextResponse.json({ items: [], attribution: geocoder.attribution, provider: geocoder.name });

  const lat = Number(sp.get('lat')), lng = Number(sp.get('lng'));
  let near: LatLng | null = Number.isFinite(lat) && Number.isFinite(lng) && sp.get('lat') && sp.get('lng') ? { lat, lng } : null;
  if (!near && sp.get('near')) near = await resolveNear(sp.get('near')!.slice(0, 120));

  const key = `${q.toLowerCase()}|${near ? `${near.lat.toFixed(2)},${near.lng.toFixed(2)}` : '-'}`;
  let items = results.get(key);
  if (!items) {
    const budget = await addressBudget(async () => await createServiceClient().rpc('consume_address_budget'));
    if (budget !== 'allowed') return NextResponse.json({ items: [], attribution: geocoder.attribution, provider: geocoder.name, unavailable: true }, { status: budget === 'limited' ? 429 : 503 });
    try {
      const found = await geocoder.search(q, { near: near ?? undefined, limit: 5, language: sp.get('lang') === 'de' ? 'de' : 'ro' });
      items = found.map((r) => ({ label: r.label, lat: r.location.lat, lng: r.location.lng, postcode: r.postalCode ?? null }));
      results.set(key, items);
    } catch {
      // Serviciul de adrese nu răspunde: clientul poate scrie adresa liber.
      return NextResponse.json({ items: [], attribution: geocoder.attribution, provider: geocoder.name, unavailable: true });
    }
  }
  return NextResponse.json({ items, attribution: geocoder.attribution, provider: geocoder.name });
}
