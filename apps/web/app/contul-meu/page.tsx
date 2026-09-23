import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getT, type MessageKey } from '@/lib/i18n';
import { createClient } from '@/lib/supabase/server';
import { cancelMyBooking, trackMyBooking } from './actions';

type Row = {
  booking_id: string; company_name: string; company_slug: string; trip_title: string; departure_at: string;
  from_name: string; to_name: string; passengers: number; status: string; price_cents: number | null;
  amount_paid_cents: number; payment_status: string; currency: string; cancel_until: string;
};

export default async function MyAccountPage({ searchParams }: {
  searchParams: Promise<{ ok?: string; paid?: string; cancelled?: string; error?: string }>;
}) {
  const q = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/login?next=/contul-meu');
  const { t, locale } = await getT();
  const { data, error } = await supabase.rpc('my_bookings');
  if (error) throw error;
  const rows = (data ?? []) as Row[];
  const lang = locale === 'de' ? 'de' : 'ro';
  const time = new Intl.DateTimeFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { timeZone: 'Europe/Bucharest', weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  const money = (cents: number, currency: string) => new Intl.NumberFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { style: 'currency', currency }).format(cents / 100);
  const statusKey = (s: string) => (['HELD', 'CONFIRMED', 'CANCELLED', 'COMPLETED'].includes(s) ? `acc.status.${s}` : 'acc.status.CONFIRMED') as MessageKey;

  return (
    <main className="market">
      <header className="market-head">
        <Link href="/cauta" className="site-brand"><span>TransportOS</span></Link>
        <Link href="/cauta">{t('mk.title')}</Link>
      </header>
      <h1>{t('acc.title')}</h1>
      {q.ok && <p className="alert alert-ok" role="status">{t('acc.ok')}</p>}
      {q.paid && <p className="alert alert-ok" role="status">{t('acc.paidOk')}</p>}
      {q.cancelled && <p className="alert alert-info" role="status">{t('acc.payCancelled')}</p>}
      {q.error && <p className="alert alert-error" role="alert">{q.error}</p>}
      {rows.length === 0 ? <p className="card">{t('acc.empty')}</p> : (
        <ul className="list" style={{ listStyle: 'none', padding: 0 }}>
          {rows.map((r) => {
            const active = ['HELD', 'CONFIRMED', 'DRIVER_ASSIGNED', 'APPROACHING', 'ARRIVED', 'ON_BOARD'].includes(r.status);
            const due = r.price_cents !== null ? Math.max(r.price_cents - r.amount_paid_cents, 0) : null;
            return (
              <li key={r.booking_id} className="card">
                <div className="offer-head"><strong>{r.company_name}</strong><span className="meta">{t(statusKey(r.status))}</span></div>
                <div className="offer-time">{time.format(new Date(r.departure_at))}</div>
                <div>{r.from_name} → {r.to_name} · {r.passengers} {t('mk.persons').toLowerCase()}</div>
                <div className="meta">
                  {t('acc.paid')}: {money(r.amount_paid_cents, r.currency)}
                  {due !== null && due > 0 ? ` · ${t('acc.due')}: ${money(due, r.currency)}` : ''}
                </div>
                {active && (
                  <div className="actions" style={{ justifyContent: 'flex-start', marginTop: 8 }}>
                    <form action={trackMyBooking}><input type="hidden" name="id" value={r.booking_id} /><button className="btn btn-small">{t('acc.track')}</button></form>
                    {new Date(r.cancel_until) > new Date() && (
                      <form action={cancelMyBooking}><input type="hidden" name="id" value={r.booking_id} /><button className="btn btn-small">{t('acc.cancel')}</button></form>
                    )}
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </main>
  );
}
