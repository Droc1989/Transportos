import { randomUUID } from 'node:crypto';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { FEATURE_LABELS, type VehicleFeature } from '@transportos/shared';
import { ActionForm } from '../../dispecerat/_components/action-form';
import { getT } from '@/lib/i18n';
import { createClient } from '@/lib/supabase/server';
import { bookSeat, saveClientProfile } from './actions';

type Offer = {
  trip_id: string; company_name: string; company_slug: string; departure_at: string; from_name: string; to_name: string;
  free_seats: number; price_cents: number | null; currency: string; has_backup_vehicle: boolean;
  vehicle: { label: string; year: number | null; features: VehicleFeature[]; photos: { kind: string; url: string }[];
    luggage_pieces: number | null; luggage_kg: number | null } | null;
  accepts_full: boolean; accepts_deposit: boolean; deposit_percent: number; accepts_cash: boolean; online_payment: boolean;
  cancel_until_hours: number;
};

export default async function BookPage({ params, searchParams }: {
  params: Promise<{ trip: string }>; searchParams: Promise<{ from?: string; to?: string; pax?: string }>;
}) {
  const { trip } = await params;
  const q = await searchParams;
  const from = Number(q.from); const to = Number(q.to);
  const pax = Math.min(Math.max(Number(q.pax) || 1, 1), 20);
  const back = `/rezerva/${trip}?from=${from}&to=${to}&pax=${pax}`;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(back)}`);
  const { t, locale } = await getT();
  const lang = locale === 'de' ? 'de' : 'ro';

  const [{ data: offers, error }, { data: profile }] = await Promise.all([
    supabase.rpc('get_marketplace_offer', { p_trip_id: trip, p_from_seq: from, p_to_seq: to, p_passengers: pax }),
    supabase.from('client_profiles').select('full_name, phone').eq('user_id', user.id).maybeSingle<{ full_name: string; phone: string }>(),
  ]);
  if (error) throw error;
  const o = ((offers ?? []) as Offer[])[0];
  const money = (cents: number) => new Intl.NumberFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { style: 'currency', currency: o?.currency ?? 'EUR' }).format(cents / 100);
  const time = new Intl.DateTimeFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { timeZone: 'Europe/Bucharest', dateStyle: 'full', timeStyle: 'short' });

  if (!o || o.free_seats < pax) {
    return <main className="market"><p className="card">{t('bk.gone')} <Link href="/cauta">{t('mk.title')}</Link></p></main>;
  }
  const total = o.price_cents !== null ? o.price_cents * pax : null;
  const deposit = total !== null ? Math.max(Math.ceil((total * o.deposit_percent) / 100), 1) : null;
  const online = o.online_payment && total !== null;

  return (
    <main className="market">
      <p><Link href="/cauta">← {t('mk.title')}</Link></p>
      <h1>{t('bk.title')}</h1>
      <section className="card offer" style={{ marginBottom: 16 }}>
        {o.vehicle?.photos?.[0] && <img src={o.vehicle.photos[0].url} alt="" className="offer-photo" />}
        <div className="offer-body">
          <strong>{o.company_name}</strong>
          <div className="offer-time">{time.format(new Date(o.departure_at))}</div>
          <div>{o.from_name} → {o.to_name} · {pax} × {o.price_cents !== null ? money(o.price_cents) : t('mk.noPrice')}</div>
          {o.vehicle && (
            <div className="feature-list" style={{ marginTop: 6 }}>
              <span>{o.vehicle.label}{o.vehicle.year ? ` · ${o.vehicle.year}` : ''}</span>
              {o.vehicle.features.map((f) => <span key={f}>{FEATURE_LABELS[lang][f] ?? f}</span>)}
            </div>
          )}
          {o.vehicle && o.vehicle.photos.length > 1 && (
            <div className="track-photos" style={{ marginTop: 8 }}>
              {o.vehicle.photos.slice(1, 5).map((p) => <img key={p.url} src={p.url} alt="" loading="lazy" />)}
            </div>
          )}
          <p className="meta">{o.has_backup_vehicle ? `${t('mk.backup')} · ` : ''}{t('mk.cancelFree').replace('{h}', String(o.cancel_until_hours))}</p>
        </div>
      </section>

      {!profile ? (
        <ActionForm action={saveClientProfile} submitLabel={t('bk.saveProfile')} pendingLabel={t('common.saving')}>
          <input type="hidden" name="back" value={back} />
          <fieldset>
            <legend>{t('bk.profile')}</legend>
            <label>{t('bk.name')}<input name="full_name" required minLength={2} maxLength={120} autoComplete="name" /></label>
            <label>{t('bk.phone')}<input name="phone" type="tel" required pattern="\+?[0-9 ]{6,24}" autoComplete="tel" /></label>
          </fieldset>
        </ActionForm>
      ) : (
        <ActionForm action={bookSeat} submitLabel={t('bk.confirm')} pendingLabel={t('common.saving')}>
          <input type="hidden" name="trip_id" value={o.trip_id} />
          <input type="hidden" name="from_seq" value={from} />
          <input type="hidden" name="to_seq" value={to} />
          <input type="hidden" name="pax" value={pax} />
          <input type="hidden" name="idempotency_key" value={randomUUID()} />
          <input type="hidden" name="label" value={`${o.company_name}, ${o.from_name} – ${o.to_name}`} />
          <fieldset>
            <legend>{profile.full_name} · {profile.phone}</legend>
            <label>{t('bk.pickup')}<input name="pickup_address" required maxLength={300} /></label>
            <label>{t('bk.notes')}<input name="pickup_notes" maxLength={500} /></label>
          </fieldset>
          <fieldset>
            <legend>{t('bk.payment')}</legend>
            {online && o.accepts_full && total !== null && (
              <label className="check"><input type="radio" name="payment" value="FULL" defaultChecked />{t('bk.payFull')} ({money(total)})</label>
            )}
            {online && o.accepts_deposit && deposit !== null && (
              <label className="check"><input type="radio" name="payment" value="DEPOSIT" defaultChecked={!o.accepts_full} />{t('bk.payDeposit').replace('{amount}', money(deposit))}</label>
            )}
            {o.accepts_cash && (
              <label className="check"><input type="radio" name="payment" value="CASH" defaultChecked={!online} />{t('bk.payCash')}{total !== null ? ` (${money(total)})` : ''}</label>
            )}
            <p className="meta" style={{ margin: 0 }}>{t('bk.paidTo').replace('{company}', o.company_name)}</p>
          </fieldset>
        </ActionForm>
      )}
    </main>
  );
}
