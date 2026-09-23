import { createClient } from '@supabase/supabase-js';
import { requireEnv } from '@/lib/env';

/**
 * Client cu cheia service_role. DOAR pe server, doar pentru webhook-ul Stripe și conectarea
 * contului Stripe (după ce s-a verificat că utilizatorul e adminul firmei). Nu se importă în
 * componente client și nu se expune în browser.
 */
export function createServiceClient() {
  return createClient(requireEnv('NEXT_PUBLIC_SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
