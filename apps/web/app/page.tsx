import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

// Super Admin ajunge în panoul lui; restul în dispecerat.
export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login');
  const { data: isAdmin } = await supabase.rpc('is_platform_admin');
  redirect(isAdmin === true ? '/admin' : '/dispecerat');
}
