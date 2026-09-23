import type { NextRequest } from 'next/server';
import { siteHostRewrite } from '@/lib/site-host';
import { updateSession } from '@/lib/supabase/middleware';

export async function middleware(request: NextRequest) {
  // Site-urile firmelor (subdomeniu sau domeniu propriu) nu au nevoie de sesiune.
  const site = await siteHostRewrite(request);
  if (site) return site;
  return updateSession(request);
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|webp)$).*)'],
};
