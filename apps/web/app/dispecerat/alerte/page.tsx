import Link from 'next/link';
import { requireStaffCompany } from '@/lib/company';
import { getT, type MessageKey } from '@/lib/i18n';
import { AutoRefresh } from '../../u/[token]/auto-refresh';
import { acknowledgeEmergency, resolveEmergency } from './actions';

type Alert = {
  kind: 'EMERGENCY' | 'PICKUP_AT_RISK' | 'PICKUP_MISSED';
  ref_id: string;
  trip_id: string | null;
  booking_id: string | null;
  severity: string;
  occurred_at: string;
  details: { distance_m?: number; status?: string; source?: string } | null;
};

export default async function AlertsPage() {
  const { supabase, companyId, timeZone } = await requireStaffCompany();
  const { t, locale } = await getT();
  const { data, error } = await supabase.rpc('get_dispatch_alerts', { p_company_id: companyId });
  if (error) throw error;
  const alerts = (data ?? []) as Alert[];

  const time = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', {
    timeZone, hour: '2-digit', minute: '2-digit',
  });

  return (
    <>
      <AutoRefresh seconds={15} />
      <h1>{t('alerts.title')}</h1>
      {alerts.length === 0 ? (
        <p className="card">{t('alerts.empty')}</p>
      ) : (
        <ul className="list" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
          {alerts.map((a) => (
            <li key={`${a.kind}-${a.ref_id}`} className={`card alert-card sev-${a.kind === 'PICKUP_AT_RISK' ? 'medium' : 'high'}`}>
              <div className="alert-head">
                <strong>{t(`alerts.${a.kind}` as MessageKey)}</strong>
                <span className="plate">{time.format(new Date(a.occurred_at))}</span>
              </div>
              <div className="meta">
                {a.kind === 'EMERGENCY'
                  ? a.severity === 'POSSIBLE' ? t('alerts.possible') : t('alerts.confirmed')
                  : a.details?.distance_m !== undefined ? `${t('alerts.distance')}: ${(a.details.distance_m / 1000).toFixed(1)} km` : null}
              </div>
              <div className="actions" style={{ justifyContent: 'flex-start', marginTop: 8 }}>
                {a.trip_id && (
                  <Link className="btn btn-small btn-link" href={`/dispecerat/curse/${a.trip_id}/opriri`}>
                    {t('alerts.openTrip')}
                  </Link>
                )}
                {a.kind === 'EMERGENCY' && (
                  <>
                    <form action={acknowledgeEmergency}>
                      <input type="hidden" name="id" value={a.ref_id} />
                      <button className="btn btn-small">{t('alerts.acknowledge')}</button>
                    </form>
                    <form action={resolveEmergency}>
                      <input type="hidden" name="id" value={a.ref_id} />
                      <button className="btn btn-small">{t('alerts.resolve')}</button>
                    </form>
                  </>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
