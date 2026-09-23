import Link from 'next/link';
import { requireStaffCompany } from '@/lib/company';
import { getT, type MessageKey } from '@/lib/i18n';
import { setRequestStatus } from './actions';

type Req = {
  id: string; full_name: string; phone: string; email: string | null; from_text: string; to_text: string;
  travel_date: string | null; passengers: number; message: string | null; status: string; created_at: string;
};

export default async function RequestsPage() {
  const { supabase, companyId, timeZone } = await requireStaffCompany();
  const { t, locale } = await getT();
  const { data, error } = await supabase
    .from('booking_requests')
    .select('id, full_name, phone, email, from_text, to_text, travel_date, passengers, message, status, created_at')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(100)
    .returns<Req[]>();
  if (error) throw error;
  const list = [...(data ?? [])].sort((a, b) => Number(b.status === 'NEW') - Number(a.status === 'NEW'));
  const fmt = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', { timeZone, dateStyle: 'medium', timeStyle: 'short' });
  const day = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', { dateStyle: 'full' });

  return (
    <>
      <h1>{t('requests.title')}</h1>
      {list.length === 0 ? <p className="card">{t('requests.empty')}</p> : (
        <ul className="list" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
          {list.map((r) => (
            <li key={r.id} className={`card${r.status === 'NEW' ? ' request-new' : ''}`}>
              <div className="alert-head">
                <strong>{r.full_name} · <a href={`tel:${r.phone}`}>{r.phone}</a></strong>
                <span className="meta">{fmt.format(new Date(r.created_at))} · {t(`requests.${r.status}` as MessageKey)}</span>
              </div>
              <div>
                {r.from_text} → {r.to_text} · {r.passengers} {t('requests.persons')}
                {r.travel_date ? ` · ${day.format(new Date(`${r.travel_date}T12:00:00`))}` : ''}
              </div>
              {r.message && <p className="meta" style={{ margin: '6px 0 0' }}>„{r.message}”</p>}
              {r.status !== 'CONVERTED' && r.status !== 'REJECTED' && (
                <div className="actions" style={{ justifyContent: 'flex-start', marginTop: 8 }}>
                  <Link
                    className="btn btn-small btn-link"
                    href={`/dispecerat/rezervare-noua?name=${encodeURIComponent(r.full_name)}&phone=${encodeURIComponent(r.phone)}&pax=${r.passengers}&request=${r.id}`}
                  >
                    {t('requests.book')}
                  </Link>
                  {r.status === 'NEW' && (
                    <form action={setRequestStatus}>
                      <input type="hidden" name="id" value={r.id} /><input type="hidden" name="status" value="CONTACTED" />
                      <button className="btn btn-small">{t('requests.contacted')}</button>
                    </form>
                  )}
                  <form action={setRequestStatus}>
                    <input type="hidden" name="id" value={r.id} /><input type="hidden" name="status" value="REJECTED" />
                    <button className="btn btn-small">{t('requests.reject')}</button>
                  </form>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
