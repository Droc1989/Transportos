import { notFound, redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

/** Panoul Super Admin: doar pentru proprietarul platformei. Restul primesc 404. */
export async function requirePlatformAdmin() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login?next=/admin');
  const { data } = await supabase.rpc('is_platform_admin');
  if (data !== true) notFound();
  return { supabase, userId: user.id };
}
