import type { Metadata } from 'next';
import Link from 'next/link';
import { FEATURE_LABELS, type VehicleFeature } from '@transportos/shared';
import { getT } from '@/lib/i18n';
import { createAnonClient } from '@/lib/supabase/anon';
import { resolvePlace, type ResolvedPlace } from '@/lib/places';
import { placeLabel } from '@/lib/place-label';
import { PlaceInput } from '../_components/place-input';
import { zonedLocalToUtc } from '@/lib/time';

export const metadata: Metadata = { title: 'Caută o cursă – TransportOS' };

type Offer = {
  trip_id: string; company_name: string; company_slug: string; departure_at: string; from_seq: number; from_name: string;
  to_seq: number; to_name: string; free_seats: number; price_cents: number | null; currency: string;
  vehicle: { label: string; seats: number; year: number | null; features: VehicleFeature[]; photos: { kind: string; url: string }[] } | null;
  has_backup_vehicle: boolean; accepts_full: boolean; accepts_deposit: boolean; accepts_cash: boolean; online_payment: boolean;
  cancel_until_hours: number;
};

export default async function SearchPage({ searchParams }: {
  searchParams: Promise<{ from?: string; to?: string; date?: string; pax?: string; lat?: string; lng?: string }>;
}) {
  const q = await searchParams;
  const { t, locale } = await getT();
  const anon = createAnonClient();
  const pax = Math.min(Math.max(Number(q.pax) || 1, 1), 20);
  const today = new Date().toISOString().slice(0, 10);
  const hasDate = !!q.date && /^\d{4}-\d{2}-\d{2}$/.test(q.date);
  const date = hasDate ? q.date! : today;
  const [fromRes, toRes] = await Promise.all([resolvePlace(anon, q.from), resolvePlace(anon, q.to)]);
  const from = fromRes.place;
  const to = toRes.place;
  // Text scris dar negăsit deloc: îi spunem. Mai multe variante: îl lăsăm să aleagă.
  const notFound = [
    q.from && !from && !fromRes.candidates.length && !(q.lat && q.lng) ? q.from : null,
    q.to && !to && !toRes.candidates.length ? q.to : null,
  ].filter((v): v is string => !!v && v.trim() !== '');
  const choose = (field: 'from' | 'to', value: string) => {
    const params = new URLSearchParams(Object.entries(q).filter(([, v]) => typeof v === 'string') as [string, string][]);
    params.set(field, value);
    return `/cauta?${params}`;
  };
  const lat = Number(q.lat), lng = Number(q.lng);
  const gps = q.lat && q.lng && Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng } : null;
  const pickup = from ?? gps;

  let offers: Offer[] | null = null;
  if (pickup && to) {
    // Cu dată: toată ziua aleasă. „Acum” (fără dată): următoarele 24 de ore.
    const start = hasDate ? zonedLocalToUtc(`${date}T00:00`, 'Europe/Bucharest')! : new Date();
    const end = new Date(start.getTime() + 24 * 3600 * 1000);
    const { data, error: sErr } = await anon.rpc('search_marketplace', {
      p_pickup_lat: pickup.lat, p_pickup_lng: pickup.lng, p_dropoff_lat: to.lat, p_dropoff_lng: to.lng,
      p_passengers: pax, p_window_start: start.toISOString(), p_window_end: end.toISOString(),
    });
    if (sErr) throw sErr;
    offers = (data ?? []) as Offer[];
  }

  const lang = locale === 'de' ? 'de' : 'ro';
  const time = new Intl.DateTimeFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { timeZone: 'Europe/Bucharest', weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  const money = (cents: number, currency: string) => new Intl.NumberFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { style: 'currency', currency }).format(cents / 100);

  return (
    <main className="market">
      <header className="market-head">
        <Link href="/cauta" className="site-brand"><span>TransportOS</span></Link>
        <Link href="/contul-meu">{t('mk.account')}</Link>
      </header>
      <h1>{t('mk.title')}</h1>
      {notFound.length > 0 && (
        <p role="alert" className="alert alert-info">
          {t('mk.notFound').replace('{name}', notFound.map((n) => `„${n.trim()}”`).join(', '))}
        </p>
      )}
      {([['from', q.from, fromRes.candidates], ['to', q.to, toRes.candidates]] as const).map(([field, value, candidates]) =>
        candidates.length > 0 && (
          <div key={field} className="alert alert-info place-choose" role="alert">
            <p>{t('mk.whichPlace').replace('{name}', `„${(value ?? '').split(',')[0]!.trim()}”`)}</p>
            <ul>
              {(candidates as ResolvedPlace[]).map((c) => (
                <li key={c.id}><Link href={choose(field, c.id)}>{placeLabel(c)}</Link> <span className="meta">{c.country}</span></li>
              ))}
            </ul>
          </div>
        ))}
      <p className="lead">{t('mk.intro')}</p>

      <form method="get" className="card market-form">
        <label>{t('mk.from')}
          {/* După o căutare cu GPS, poziția rămâne în formular pentru o nouă căutare. */}
          {gps && !from && <><input type="hidden" name="lat" value={gps.lat} /><input type="hidden" name="lng" value={gps.lng} /></>}
          <PlaceInput key={`from-${from?.id ?? q.from ?? ''}-${gps ? 'gps' : ''}`} name="from" defaultText={from ? placeLabel(from) : gps ? t('mk.myLocation') : (q.from ?? '')}
            defaultId={from?.id ?? ''} keepText={gps && !from ? t('mk.myLocation') : undefined} required={!gps || !!from}
            noResults={t('mk.noPlace')} />
        </label>
        <label>{t('mk.to')}
          <PlaceInput key={`to-${to?.id ?? q.to ?? ''}`} name="to" defaultText={to ? placeLabel(to) : (q.to ?? '')} defaultId={to?.id ?? ''} required
            noResults={t('mk.noPlace')} />
        </label>
        <label>{t('mk.date')}<input type="date" name="date" defaultValue={date} min={today} required /></label>
        <label>{t('mk.persons')}<input type="number" name="pax" min={1} max={20} defaultValue={pax} required /></label>
        <button className="btn btn-primary">{t('mk.search')}</button>
      </form>

      {offers && offers.length === 0 && <p className="card">{t('mk.none')}</p>}
      {offers && offers.length > 0 && (
        <ul className="list" style={{ listStyle: 'none', padding: 0 }}>
          {offers.map((o) => (
            <li key={o.trip_id} className="card offer">
              {o.vehicle?.photos?.[0] && <img src={o.vehicle.photos[0].url} alt="" className="offer-photo" loading="lazy" />}
              <div className="offer-body">
                <div className="offer-head">
                  <strong>{o.company_name}</strong>
                  <Link href={`/f/${o.company_slug}`} className="meta">{t('mk.site')}</Link>
                </div>
                <div className="offer-time">{time.format(new Date(o.departure_at))}</div>
                <div>{o.from_name} → {o.to_name} · {o.free_seats} {t('mk.seats')}</div>
                {o.vehicle && (
                  <div className="feature-list" style={{ marginTop: 6 }}>
                    <span>{o.vehicle.label}{o.vehicle.year ? ` · ${o.vehicle.year}` : ''}</span>
                    {o.vehicle.features.map((f) => <span key={f}>{FEATURE_LABELS[lang][f] ?? f}</span>)}
                  </div>
                )}
                <div className="meta" style={{ marginTop: 6 }}>
                  {o.has_backup_vehicle ? `${t('mk.backup')} · ` : ''}
                  {[o.online_payment && (o.accepts_full || o.accepts_deposit) ? t('mk.onlinePay') : null, o.accepts_cash ? t('mk.cashPay') : null].filter(Boolean).join(' · ')}
                  {' · '}{t('mk.cancelFree').replace('{h}', String(o.cancel_until_hours))}
                </div>
              </div>
              <div className="offer-price">
                {o.price_cents !== null ? (
                  <>
                    <strong>{money(o.price_cents, o.currency)}</strong>
                    <span className="meta">{t('mk.perPerson')}</span>
                    {pax > 1 && <span className="meta">{money(o.price_cents * pax, o.currency)} {t('mk.total')}</span>}
                  </>
                ) : <span className="meta">{t('mk.noPrice')}</span>}
                <Link className="btn btn-primary btn-link" href={`/rezerva/${o.trip_id}?from=${o.from_seq}&to=${o.to_seq}&pax=${pax}${pickup ? `&plat=${pickup.lat.toFixed(4)}&plng=${pickup.lng.toFixed(4)}` : ''}`}>{t('mk.book')}</Link>
              </div>
            </li>
          ))}
        </ul>
      )}
      <p className="meta" style={{ marginTop: 24 }}>{t('mk.placesSource')}</p>
    </main>
  );
}
