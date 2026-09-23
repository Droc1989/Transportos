import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { StopKind, StopStatus } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { ShareButton } from '../../../_components/share-button';
import { autoOrder, computeTimes, createTrackingLink, moveStop } from './actions';

type Stop = {
  id: string;
  booking_id: string;
  seq: number;
  kind: StopKind;
  status: StopStatus;
  address: string | null;
  planned_at: string | null;
  customer_name: string;
  customer_phone: string;
  passengers: number;
  pickup_notes: string | null;
};

export default async function TripStopsPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ error?: string; times?: string }>;
}) {
  const { id } = await params;
  const { error, times } = await searchParams;
  const { supabase, companyId, timeZone } = await requireStaffCompany();
  const { t, locale } = await getT();

  const [trip, stops] = await Promise.all([
    supabase
      .from('trips')
      .select('id, title, status, departure_at')
      .eq('id', id)
      .eq('company_id', companyId)
      .maybeSingle<{ id: string; title: string; status: string; departure_at: string }>(),
    supabase.rpc('get_trip_stops', { p_trip_id: id }),
  ]);
  if (trip.error) throw trip.error;
  if (stops.error) throw stops.error;
  if (!trip.data) notFound();

  const list = (stops.data ?? []) as Stop[];
  const open = ['PLANNED', 'IN_PROGRESS'].includes(trip.data.status);
  const time = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
  });
  const day = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', {
    timeZone,
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });
  const departure = new Date(trip.data.departure_at);

  return (
    <>
      <h1>{t('stops.title')}</h1>
      <p className="lead">
        {trip.data.title} · {t('stops.departure')} {day.format(departure)}, {time.format(departure)} ·{' '}
        <Link href={`/dispecerat/curse/${id}`}>{t('editTrip.edit')}</Link> ·{' '}
        <Link href={`/dispecerat/curse/${id}/pasageri`}>{t('pax.link')}</Link>
      </p>

      {error && <p role="alert" className="alert alert-error">{error}</p>}
      {times === 'approximate' && <p role="status" className="alert alert-info">{t('stops.approximate')}</p>}
      {times === 'ok' && <p role="status" className="alert alert-ok">{t('stops.timesSaved')} {t('stops.noTraffic')}</p>}

      {list.length === 0 ? (
        <p className="card">{t('stops.empty')}</p>
      ) : (
        <>
          {open && (
            <div className="toolbar">
              <form action={autoOrder}>
                <input type="hidden" name="trip_id" value={id} />
                <button className="btn btn-small">{t('stops.autoOrder')}</button>
              </form>
              <form action={computeTimes}>
                <input type="hidden" name="trip_id" value={id} />
                <button className="btn btn-primary">{t('stops.computeTimes')}</button>
              </form>
            </div>
          )}
          <p className="meta">{t('stops.hint')}</p>

          <ol className="stop-list">
            {list.map((s, i) => {
              const done = s.status === 'ARRIVED' || s.status === 'DONE';
              return (
                <li key={s.id} className={`stop-row${done ? ' is-done' : ''}`}>
                  <span className="stop-time">{s.planned_at ? time.format(new Date(s.planned_at)) : '—'}</span>
                  <span className={`stop-kind kind-${s.kind.toLowerCase()}`}>
                    {s.kind === 'PICKUP' ? t('stops.pickup') : t('stops.dropoff')}
                  </span>
                  <div className="stop-body">
                    <div>
                      <strong>{s.customer_name}</strong> · {s.passengers} {t('stops.persons')} ·{' '}
                      <a href={`tel:${s.customer_phone}`}>{s.customer_phone}</a>
                      {done && <span className="meta"> · {t('stops.arrived')}</span>}
                    </div>
                    <div className="meta">
                      {s.address ?? '—'}
                      {s.kind === 'PICKUP' && s.pickup_notes ? ` · „${s.pickup_notes}”` : ''}
                    </div>
                    {s.kind === 'PICKUP' && !done && open && (
                      <div style={{ marginTop: 6 }}>
                        <ShareButton
                          action={createTrackingLink}
                          fields={{ booking_id: s.booking_id }}
                          phone={s.customer_phone}
                          labels={{
                            button: t('track.button'),
                            title: t('track.title'),
                            help: t('track.help'),
                            copy: t('invite.copy'),
                            copied: t('invite.copied'),
                            whatsapp: t('invite.whatsapp'),
                            message: t('track.message'),
                          }}
                        />
                      </div>
                    )}
                  </div>
                  {open && !done && (
                    <div className="stop-move">
                      <form action={moveStop}>
                        <input type="hidden" name="trip_id" value={id} />
                        <input type="hidden" name="stop_id" value={s.id} />
                        <input type="hidden" name="delta" value="-1" />
                        <button className="btn btn-small" aria-label={t('common.up')} disabled={i === 0}>↑</button>
                      </form>
                      <form action={moveStop}>
                        <input type="hidden" name="trip_id" value={id} />
                        <input type="hidden" name="stop_id" value={s.id} />
                        <input type="hidden" name="delta" value="1" />
                        <button className="btn btn-small" aria-label={t('common.down')} disabled={i === list.length - 1}>
                          ↓
                        </button>
                      </form>
                    </div>
                  )}
                </li>
              );
            })}
          </ol>
        </>
      )}
    </>
  );
}
