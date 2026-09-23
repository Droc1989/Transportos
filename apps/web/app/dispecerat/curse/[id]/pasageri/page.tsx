import { notFound } from 'next/navigation';
import type { BookingStatus, PaymentMethod } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { getT, type MessageKey } from '@/lib/i18n';
import { PrintButton } from './print-button';

type Row = {
  booking_id: string;
  full_name: string;
  phone: string;
  passengers: number;
  seats: number[] | null;
  from_name: string;
  to_name: string;
  pickup_address: string | null;
  pickup_notes: string | null;
  luggage_notes: string | null;
  payment_method: PaymentMethod;
  price_cents: number | null;
  currency: string;
  status: BookingStatus;
  amount_paid_cents: number;
  amount_due_cents: number;
};

type Trip = {
  title: string;
  departure_at: string;
  vehicles: { label: string; plate: string | null } | null;
  drivers: { full_name: string } | null;
};

export default async function PassengerListPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, companyId, companyName, timeZone } = await requireStaffCompany();
  const { t, locale } = await getT();

  const [trip, rows] = await Promise.all([
    supabase
      .from('trips')
      .select('title, departure_at, vehicles(label, plate), drivers(full_name)')
      .eq('id', id)
      .eq('company_id', companyId)
      .maybeSingle<Trip>(),
    supabase.rpc('get_passenger_manifest', { p_trip_id: id }),
  ]);
  if (trip.error) throw trip.error;
  if (rows.error) throw rows.error;
  if (!trip.data) notFound();

  const list = (rows.data ?? []) as Row[];
  const total = list.reduce((sum, r) => sum + r.passengers, 0);
  const fmt = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', {
    timeZone, dateStyle: 'full', timeStyle: 'short',
  });
  const money = (cents: number | null, currency: string) =>
    cents === null ? '—' : new Intl.NumberFormat(locale === 'de' ? 'de-AT' : 'ro-RO', { style: 'currency', currency }).format(cents / 100);

  return (
    <article className="manifest">
      <header className="manifest-head">
        <div>
          <h1>{t('pax.title')}</h1>
          <p className="manifest-meta">
            <strong>{companyName}</strong> · {trip.data.title}
            <br />
            {fmt.format(new Date(trip.data.departure_at))}
            <br />
            {t('pax.vehicle')}: {trip.data.vehicles?.label} {trip.data.vehicles?.plate ?? ''} · {t('pax.driver')}:{' '}
            {trip.data.drivers?.full_name ?? '—'}
          </p>
        </div>
        <PrintButton label={t('pax.print')} />
      </header>

      <table className="table manifest-table">
        <thead>
          <tr>
            <th>#</th>
            <th>{t('drivers.name')}</th>
            <th>{t('drivers.phone')}</th>
            <th>{t('booking.passengers')}</th>
            <th>{t('pax.seat')}</th>
            <th>{t('pax.segment')}</th>
            <th>{t('pax.pickup')}</th>
            <th>{t('pax.payment')}</th>
          </tr>
        </thead>
        <tbody>
          {list.map((r, i) => (
            <tr key={r.booking_id}>
              <td>{i + 1}</td>
              <td><strong>{r.full_name}</strong></td>
              <td>{r.phone}</td>
              <td>{r.passengers}</td>
              <td>{r.seats?.join(', ') ?? '—'}</td>
              <td>{r.from_name} – {r.to_name}</td>
              <td>
                {r.pickup_address ?? '—'}
                {r.pickup_notes ? <div className="meta">„{r.pickup_notes}”</div> : null}
                {r.luggage_notes ? <div className="meta">{r.luggage_notes}</div> : null}
              </td>
              <td>
                {t(`payment.${r.payment_method}` as MessageKey)}
                <div className="meta">{money(r.price_cents, r.currency)}</div>
                {r.amount_paid_cents > 0 && <div className="meta">{t('acc.paid')}: {money(r.amount_paid_cents, r.currency)}</div>}
                {r.amount_due_cents > 0 && <div><strong>{t('acc.due')}: {money(r.amount_due_cents, r.currency)}</strong></div>}
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <td colSpan={3}><strong>{t('pax.total')}</strong></td>
            <td><strong>{total}</strong></td>
            <td colSpan={4} />
          </tr>
        </tfoot>
      </table>
      <p className="meta">
        {t('pax.generated')} {fmt.format(new Date())}
      </p>
    </article>
  );
}
