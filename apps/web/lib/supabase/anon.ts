import { createClient } from '@supabase/supabase-js';
import { requireEnv } from '@/lib/env';

/** Client fără sesiune, pentru paginile publice (ex. linkul de urmărire). */
export function createAnonClient() {
  return createClient(requireEnv('NEXT_PUBLIC_SUPABASE_URL'), requireEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
