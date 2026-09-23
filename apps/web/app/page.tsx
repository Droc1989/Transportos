import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

// Vizitatorii ajung la căutare; Super Admin în panoul lui; personalul firmelor în dispecerat;
// șoferii la profilul lor; clienții la rezervările lor.
export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/cauta');
  const { data: isAdmin } = await supabase.rpc('is_platform_admin');
  if (isAdmin === true) redirect('/admin');
  const { data: roles } = await supabase.from('company_members').select('role').eq('user_id', user.id);
  const list = (roles ?? []).map((r) => r.role as string);
  if (list.some((r) => r !== 'DRIVER')) redirect('/dispecerat');
  if (list.includes('DRIVER')) redirect('/sofer');
  redirect('/contul-meu');
}
