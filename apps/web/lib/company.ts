import { redirect } from 'next/navigation';
import type { MemberRole } from '@transportos/shared';
import { createClient } from '@/lib/supabase/server';

const STAFF_ROLES: MemberRole[] = ['OWNER', 'ADMIN', 'DISPATCHER'];

const COMPANY_TIME_ZONES = {
  RO: 'Europe/Bucharest',
  AT: 'Europe/Vienna',
  DE: 'Europe/Berlin',
} as const;

/**
 * Firma în care utilizatorul curent e personal (proprietar, admin sau dispecer).
 * RLS rămâne protecția reală; aici doar alegem firma pentru interfață.
 */
export async function requireStaffCompany() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login');

  const { data, error } = await supabase
    .from('company_members')
    .select('company_id, role, companies(name, country)')
    .eq('user_id', user.id)
    .in('role', STAFF_ROLES)
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  if (!data) redirect('/login?error=no_company');

  const company = data.companies as unknown as { name: string; country: 'RO' | 'AT' | 'DE' } | null;
  const country = company?.country ?? 'RO';
  return {
    supabase,
    userId: user.id,
    companyId: data.company_id as string,
    companyName: company?.name ?? '',
    role: data.role as MemberRole,
    isAdmin: data.role === 'OWNER' || data.role === 'ADMIN',
    country,
    timeZone: COMPANY_TIME_ZONES[country],
  };
}
