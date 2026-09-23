import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { FEATURE_LABELS, type VehicleFeature } from '@transportos/shared';
import { createAnonClient } from '@/lib/supabase/anon';
import { AutoRefresh } from './auto-refresh';

// Pagina clientului: fără cont, doar cu tokenul din link. Nu se indexează.
export const metadata: Metadata = { robots: { index: false, follow: false } };
export const dynamic = 'force-dynamic';

type Tracking = {
  company: string;
  booking_status: string;
  passengers: number;
  trip_title: string;
  trip_status: string;
  departure_at: string;
  pickup: {
    address: string | null;
    notes: string | null;
    planned_at: string | null;
    eta_at: string | null;
    status: string;
    lat: number | null;
    lng: number | null;
  };
  stops_before: number;
  driver_first_name: string | null;
  vehicle: { label: string; plate: string | null; seats: number } | null;
  vehicle_position: { lat: number; lng: number; recorded_at: string } | null;
  locale: 'ro' | 'de' | 'en';
};

const text = {
  ro: {
    title: 'Cursa ta',
    arrivesIn: 'Microbuzul ajunge la tine în',
    minutes: 'minute',
    around: 'Preluare estimată',
    stopsBefore: (n: number) => (n === 1 ? 'Mai are o oprire înaintea ta.' : `Mai are ${n} opriri înaintea ta.`),
    next: 'Ești următoarea oprire.',
    arrived: 'Șoferul a ajuns la punctul de preluare.',
    onBoard: 'Ești la bord. Drum bun!',
    completed: 'Ai ajuns. Mulțumim că ai călătorit cu noi!',
    cancelled: 'Rezervarea a fost anulată. Pentru detalii, contactează firma.',
    noShow: 'Rezervarea a fost marcată ca neprezentare. Contactează firma.',
    notStarted: 'Cursa nu a pornit încă.',
    departure: 'Plecare',
    pickupAt: 'Preluare',
    driver: 'Șofer',
    vehicle: 'Vehicul',
    persons: 'persoane',
    mapNote: 'Poziția microbuzului se actualizează automat.',
    yourVehicle: 'Microbuzul tău',
    year: 'din',
    luggage: 'Bagaj inclus',
    privacy: 'Vezi poziția microbuzului doar cât cursa ta e activă.',
    notesLabel: 'Indicațiile tale',
  },
  de: {
    title: 'Deine Fahrt',
    arrivesIn: 'Der Kleinbus ist bei dir in',
    minutes: 'Minuten',
    around: 'Voraussichtliche Abholung',
    stopsBefore: (n: number) => (n === 1 ? 'Noch ein Halt vor dir.' : `Noch ${n} Halte vor dir.`),
    next: 'Du bist der nächste Halt.',
    arrived: 'Der Fahrer ist am Abholort angekommen.',
    onBoard: 'Du bist an Bord. Gute Fahrt!',
    completed: 'Du bist angekommen. Danke, dass du mit uns gefahren bist!',
    cancelled: 'Die Buchung wurde storniert. Bitte wende dich an die Firma.',
    noShow: 'Die Buchung wurde als nicht erschienen markiert. Bitte wende dich an die Firma.',
    notStarted: 'Die Fahrt hat noch nicht begonnen.',
    departure: 'Abfahrt',
    pickupAt: 'Abholung',
    driver: 'Fahrer',
    vehicle: 'Fahrzeug',
    persons: 'Personen',
    mapNote: 'Die Position des Kleinbusses wird automatisch aktualisiert.',
    yourVehicle: 'Dein Kleinbus',
    year: 'Baujahr',
    luggage: 'Inklusive Gepäck',
    privacy: 'Die Position ist nur sichtbar, solange deine Fahrt aktiv ist.',
    notesLabel: 'Deine Hinweise',
  },
} as const;

function osmEmbed(points: { lat: number; lng: number }[], marker: { lat: number; lng: number }) {
  const lats = points.map((p) => p.lat);
  const lngs = points.map((p) => p.lng);
  const pad = 0.02;
  const bbox = [Math.min(...lngs) - pad, Math.min(...lats) - pad, Math.max(...lngs) + pad, Math.max(...lats) + pad]
    .map((n) => n.toFixed(5))
    .join(',');
  return `https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${marker.lat.toFixed(5)},${marker.lng.toFixed(5)}`;
}

export default async function TrackingPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const anon = createAnonClient();
  const [{ data, error }, { data: vehicleData }] = await Promise.all([
    anon.rpc('get_tracking', { p_token: token }),
    anon.rpc('get_tracking_vehicle', { p_token: token }),
  ]);
  if (error) throw error;
  if (!data) notFound();
  const vehicleInfo = vehicleData as {
    year: number | null; features: VehicleFeature[]; luggage_pieces: number | null; luggage_kg: number | null;
    photos: { kind: string; url: string }[];
  } | null;

  const d = data as Tracking;
  const lang = d.locale === 'de' ? 'de' : 'ro';
  const t = text[lang];
  const fmt = new Intl.DateTimeFormat(lang === 'de' ? 'de-AT' : 'ro-RO', {
    timeZone: lang === 'de' ? 'Europe/Vienna' : 'Europe/Bucharest',
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });

  const eta = d.pickup.eta_at ?? d.pickup.planned_at;
  const minutesLeft = eta ? Math.round((new Date(eta).getTime() - Date.now()) / 60000) : null;
  const active = !['CANCELLED', 'NO_SHOW', 'COMPLETED'].includes(d.booking_status);

  let headline: string;
  if (d.booking_status === 'CANCELLED') headline = t.cancelled;
  else if (d.booking_status === 'NO_SHOW') headline = t.noShow;
  else if (d.booking_status === 'COMPLETED') headline = t.completed;
  else if (d.booking_status === 'ON_BOARD') headline = t.onBoard;
  else if (d.booking_status === 'ARRIVED') headline = t.arrived;
  else if (d.trip_status !== 'IN_PROGRESS') headline = t.notStarted;
  else headline = d.stops_before === 0 ? t.next : t.stopsBefore(d.stops_before);

  const showCountdown =
    active && d.trip_status === 'IN_PROGRESS' && !['ARRIVED', 'ON_BOARD'].includes(d.booking_status)
    && minutesLeft !== null && minutesLeft >= 0 && minutesLeft <= 120;

  const pickupPoint = d.pickup.lat !== null && d.pickup.lng !== null ? { lat: d.pickup.lat, lng: d.pickup.lng } : null;
  const mapUrl = d.vehicle_position
    ? osmEmbed(pickupPoint ? [d.vehicle_position, pickupPoint] : [d.vehicle_position], d.vehicle_position)
    : null;

  return (
    <main className="track" lang={lang}>
      {active && <AutoRefresh seconds={30} />}
      <p className="track-company">{d.company}</p>
      <h1>{t.title}</h1>

      <div className="track-sign" role="status">
        <div className="track-sign-inner">
          {showCountdown ? (
            <>
              <span>{t.arrivesIn}</span>
              <strong>
                {minutesLeft} {t.minutes}
              </strong>
            </>
          ) : (
            <strong className="track-sign-text">{headline}</strong>
          )}
          {eta && active && (
            <span className="track-eta">
              {t.around}: {fmt.format(new Date(eta))}
            </span>
          )}
        </div>
      </div>
      {showCountdown && <p className="track-sub">{headline}</p>}

      {mapUrl && (
        <figure className="track-map">
          <iframe title="Hartă" src={mapUrl} loading="lazy" />
          <figcaption className="meta">{t.mapNote}</figcaption>
        </figure>
      )}

      <dl className="track-details">
        <div>
          <dt>{t.departure}</dt>
          <dd>
            {d.trip_title}, {fmt.format(new Date(d.departure_at))}
          </dd>
        </div>
        <div>
          <dt>{t.pickupAt}</dt>
          <dd>
            {d.pickup.address ?? '—'} · {d.passengers} {t.persons}
          </dd>
        </div>
        {d.pickup.notes && (
          <div>
            <dt>{t.notesLabel}</dt>
            <dd>„{d.pickup.notes}”</dd>
          </div>
        )}
        {d.driver_first_name && (
          <div>
            <dt>{t.driver}</dt>
            <dd>{d.driver_first_name}</dd>
          </div>
        )}
        {d.vehicle && (
          <div>
            <dt>{t.vehicle}</dt>
            <dd>
              {d.vehicle.label}
              {d.vehicle.plate ? <span className="plate-badge">{d.vehicle.plate}</span> : null}
            </dd>
          </div>
        )}
      </dl>
      {vehicleInfo && (vehicleInfo.photos.length > 0 || vehicleInfo.features.length > 0) && (
        <section className="track-vehicle">
          <h2>{t.yourVehicle}{vehicleInfo.year ? <span className="meta"> · {t.year} {vehicleInfo.year}</span> : null}</h2>
          {vehicleInfo.photos.length > 0 && (
            <div className="track-photos">
              {vehicleInfo.photos.slice(0, 4).map((p) => <img key={p.url} src={p.url} alt="" loading="lazy" />)}
            </div>
          )}
          <div className="feature-list">
            {vehicleInfo.features.map((f) => <span key={f}>{FEATURE_LABELS[lang][f] ?? f}</span>)}
          </div>
          {vehicleInfo.luggage_pieces !== null && (
            <p className="meta">{t.luggage}: {vehicleInfo.luggage_pieces} × {vehicleInfo.luggage_kg ?? '—'} kg</p>
          )}
        </section>
      )}
      <p className="meta">{t.privacy}</p>
    </main>
  );
}
