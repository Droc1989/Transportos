import { NextResponse, type NextRequest } from 'next/server';
import { createAnonClient } from '@/lib/supabase/anon';

// Sugestii de localități pentru câmpurile de căutare (public, doar citire).
export async function GET(request: NextRequest) {
  const q = (request.nextUrl.searchParams.get('q') ?? '').slice(0, 80);
  const country = request.nextUrl.searchParams.get('country');
  if (q.trim().length < 2) return NextResponse.json([]);
  const { data, error } = await createAnonClient().rpc('search_places', {
    p_query: q,
    p_country: country && /^[A-Za-z]{2}$/.test(country) ? country : null,
    p_limit: 8,
  });
  if (error) return NextResponse.json([], { status: 500 });
  return NextResponse.json(data ?? [], { headers: { 'Cache-Control': 'public, max-age=300' } });
}
