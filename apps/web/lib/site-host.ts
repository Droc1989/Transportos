import { NextResponse, type NextRequest } from 'next/server';

// Subdomenii ale platformei care nu sunt site-uri de firme.
const RESERVED = new Set(['www', 'app', 'admin', 'api', 'mail', 'static', 'cdn']);
const CACHE_TTL_MS = 5 * 60 * 1000;
const domainCache = new Map<string, { slug: string | null; at: number }>();

async function lookupCustomDomain(host: string): Promise<string | null> {
  const cached = domainCache.get(host);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.slug;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return null;
  try {
    const res = await fetch(`${url}/rest/v1/rpc/resolve_site_domain`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_host: host }),
    });
    const slug = res.ok ? ((await res.json()) as string | null) : null;
    domainCache.set(host, { slug, at: Date.now() });
    return slug;
  } catch {
    return null;
  }
}

/**
 * Dacă cererea vine pe <slug>.<NEXT_PUBLIC_ROOT_DOMAIN> sau pe domeniul propriu al unei firme,
 * o rescrie către /f/<slug>/… și marchează că linkurile interne nu au prefix.
 */
export async function siteHostRewrite(request: NextRequest): Promise<NextResponse | null> {
  const root = process.env.NEXT_PUBLIC_ROOT_DOMAIN?.toLowerCase();
  if (!root) return null;
  const host = (request.headers.get('host') ?? '').split(':')[0]!.toLowerCase();
  if (!host || host === root || host === 'localhost' || /^\d+(\.\d+){3}$/.test(host)) return null;

  let slug: string | null = null;
  if (host.endsWith(`.${root}`)) {
    const sub = host.slice(0, -(root.length + 1));
    if (sub.includes('.') || RESERVED.has(sub)) return null;
    slug = sub;
  } else {
    slug = await lookupCustomDomain(host);
  }
  if (!slug) return null;

  const path = request.nextUrl.pathname;
  const url = request.nextUrl.clone();
  url.pathname = `/f/${slug}${path === '/' ? '' : path}`;
  const headers = new Headers(request.headers);
  headers.set('x-site-base', '');
  return NextResponse.rewrite(url, { request: { headers } });
}
