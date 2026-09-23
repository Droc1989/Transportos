import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { requireEnv } from '@/lib/env';

/** Client Supabase pentru Server Components și Server Actions (sesiunea din cookie). */
export async function createClient() {
  const cookieStore = await cookies();
  return createServerClient(
    requireEnv('NEXT_PUBLIC_SUPABASE_URL'),
    requireEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY'),
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Apelat dintr-un Server Component: middleware-ul reîmprospătează sesiunea.
          }
        },
      },
    },
  );
}
