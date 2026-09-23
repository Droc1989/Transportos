import type { ReactNode } from 'react';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { signOut } from '../login/actions';
import { Nav } from './nav';

export default async function DispatchLayout({ children }: { children: ReactNode }) {
  const { companyName, supabase, companyId, isActive } = await requireStaffCompany({ allowPending: true });
  const { data: alerts } = await supabase.rpc('get_dispatch_alerts', { p_company_id: companyId });
  const alertCount = Array.isArray(alerts) ? alerts.length : 0;
  const { data: requests } = await supabase.rpc('count_new_booking_requests', { p_company_id: companyId });
  const requestCount = typeof requests === 'number' ? requests : 0;
  const { t } = await getT();
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          TransportOS
          <div style={{ fontSize: 13, fontWeight: 600, color: '#b9c4d3' }}>{companyName}</div>
        </div>
        {!isActive ? (
          <nav aria-label="Înscriere" style={{ display: 'contents' }}>
            <a href="/dispecerat/inscriere">{t('nav.registration')}</a>
            <a href="/dispecerat/vehicule">{t('nav.vehicles')}</a>
          </nav>
        ) : (
        <Nav
          alertCount={alertCount}
          requestCount={requestCount}
          labels={{
            trips: t('nav.trips'),
            alerts: t('nav.alerts'),
            requests: t('nav.requests'),
            site: t('nav.site'),
            team: t('nav.team'),
            export: t('nav.export'),
            newBooking: t('nav.newBooking'),
            newTrip: t('nav.newTrip'),
            routes: t('nav.routes'),
            vehicles: t('nav.vehicles'),
            drivers: t('nav.drivers'),
          }}
        />
        )}
        <form action={signOut}>
          <button className="btn btn-ghost">{t('nav.logout')}</button>
        </form>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
