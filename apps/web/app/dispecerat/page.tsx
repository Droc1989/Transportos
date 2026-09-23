import Link from 'next/link';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';

type TripRow = {
  id: string;
  title: string;
  departure_at: string;
  status: string;
  vehicles: { label: string; seats: number } | null;
  drivers: { full_name: string } | null;
  trip_route_points: { seq: number; name: string }[];
  bookings: { status: string }[];
};

const ACTIVE_BOOKING = new Set(['HELD', 'CONFIRMED', 'DRIVER_ASSIGNED', 'APPROACHING', 'ARRIVED', 'ON_BOARD']);

export default async function DispatchHome({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; created?: string; updated?: string; cancelled?: string }>;
}) {
  const { ok, created, updated, cancelled } = await searchParams;
  const { supabase, companyId } = await requireStaffCompany();
  const { t, locale } = await getT();

  const { data, error } = await supabase
    .from('trips')
    .select(
      'id, title, departure_at, status, vehicles(label, seats), drivers(full_name), trip_route_points(seq, name), bookings(status)',
    )
    .eq('company_id', companyId)
    .in('status', ['PLANNED', 'IN_PROGRESS'])
    .gte('departure_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
    .order('departure_at')
    .limit(50)
    .returns<TripRow[]>();
  if (error) throw error;

  // Locuri libere pe tot traseul, calculate de baza de date (sursa de adevăr).
  const trips = await Promise.all(
    (data ?? []).map(async (trip) => {
      const lastSeq = Math.max(...trip.trip_route_points.map((p) => p.seq));
      const { data: free } = await supabase.rpc('free_seats', {
        p_trip_id: trip.id,
        p_from_seq: 0,
        p_to_seq: lastSeq,
      });
      return { ...trip, freeSeats: typeof free === 'number' ? free : null };
    }),
  );

  const fmt = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });

  return (
    <>
      <h1>{t('trips.title')}</h1>
      {ok && <p className="alert alert-ok" role="status">{t('booking.saved')}</p>}
      {created && <p className="alert alert-ok" role="status">{t('trip.created')}</p>}
      {updated && <p className="alert alert-ok" role="status">{t('editTrip.updated')}</p>}
      {cancelled && (
        <p className="alert alert-info" role="status">
          {t('editTrip.cancelled')} {cancelled}
        </p>
      )}
      {trips.length === 0 ? (
        <p className="card">{t('trips.empty')}</p>
      ) : (
        <ul className="list" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
          {trips.map((trip) => (
            <li key={trip.id} className="card trip">
              <div>
                <div style={{ fontWeight: 800, fontSize: 18 }}>{trip.title}</div>
                <div className="meta">
                  {fmt.format(new Date(trip.departure_at))} ·{' '}
                  <span className="plate">{trip.vehicles?.label}</span> ·{' '}
                  {trip.drivers?.full_name ?? t('trips.noDriver')} ·{' '}
                  {trip.bookings.filter((b) => ACTIVE_BOOKING.has(b.status)).length} {t('trips.bookings')}
                </div>
              </div>
              <div className="actions">
                {trip.freeSeats !== null && (
                  <span className="pill" title={t('trips.freeSeats')}>
                    {trip.freeSeats} / {trip.vehicles?.seats}
                  </span>
                )}
                <Link className="btn btn-small btn-link" href={`/dispecerat/curse/${trip.id}/opriri`}>
                  {t('stops.link')}
                </Link>
                <Link className="btn btn-small btn-link" href={`/dispecerat/curse/${trip.id}`}>
                  {t('editTrip.edit')}
                </Link>
              </div>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
