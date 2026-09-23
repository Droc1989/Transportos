import { redirect } from 'next/navigation';
import type { MemberRole } from '@transportos/shared';
import { createClient } from '@/lib/supabase/server';

const STAFF_ROLES: MemberRole[] = ['OWNER', 'ADMIN', 'DISPATCHER'];

const COMPANY_TIME_ZONES = {
  RO: 'Europe/Bucharest',
  AT: 'Europe/Vienna',
  DE: 'Europe/Berlin',
} as const;

export type CompanyStatus = 'PENDING_VERIFICATION' | 'ACTIVE' | 'SUSPENDED' | 'REJECTED';

/**
 * Firma în care utilizatorul curent e personal (proprietar, admin sau dispecer).
 * RLS rămâne protecția reală; aici doar alegem firma și pagina potrivită.
 *
 * O firmă neaprobată (în verificare sau respinsă) are acces doar la paginile marcate cu
 * `allowPending` (înscriere, microbuze); celelalte o trimit la /dispecerat/inscriere.
 */
export async function requireStaffCompany(opts: { allowPending?: boolean } = {}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login');

  const { data, error } = await supabase
    .from('company_members')
    .select('company_id, role, companies(name, country, status)')
    .eq('user_id', user.id)
    .in('role', STAFF_ROLES)
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    // Șoferii au profilul lor; cine nu are nicio firmă își poate înscrie una.
    const { data: driver } = await supabase.from('company_members').select('role')
      .eq('user_id', user.id).eq('role', 'DRIVER').limit(1).maybeSingle();
    redirect(driver ? '/sofer' : '/inregistrare-firma');
  }

  const company = data.companies as unknown as { name: string; country: 'RO' | 'AT' | 'DE'; status: CompanyStatus } | null;
  const country = company?.country ?? 'RO';
  const status = company?.status ?? 'PENDING_VERIFICATION';
  if (!opts.allowPending && (status === 'PENDING_VERIFICATION' || status === 'REJECTED')) {
    redirect('/dispecerat/inscriere');
  }
  return {
    supabase,
    userId: user.id,
    companyId: data.company_id as string,
    companyName: company?.name ?? '',
    role: data.role as MemberRole,
    isAdmin: data.role === 'OWNER' || data.role === 'ADMIN',
    country,
    status,
    isActive: status === 'ACTIVE',
    timeZone: COMPANY_TIME_ZONES[country],
  };
}
