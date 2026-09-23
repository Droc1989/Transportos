import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { utcToZonedLocal } from '@/lib/time';
import { ActionForm } from '../../_components/action-form';
import { cancelTrip, updateTrip } from './actions';

type Trip = {
  id: string;
  title: string;
  status: string;
  departure_at: string;
  vehicle_id: string;
  driver_id: string | null;
  trip_route_points: { seq: number; name: string }[];
};

export default async function EditTripPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, companyId, timeZone } = await requireStaffCompany();
  const { t } = await getT();

  const [trip, vehicles, drivers] = await Promise.all([
    supabase
      .from('trips')
      .select('id, title, status, departure_at, vehicle_id, driver_id, trip_route_points(seq, name)')
      .eq('id', id)
      .eq('company_id', companyId)
      .maybeSingle<Trip>(),
    supabase
      .from('vehicles')
      .select('id, label, seats, is_standby')
      .eq('company_id', companyId)
      .order('label')
      .returns<{ id: string; label: string; seats: number; is_standby: boolean }[]>(),
    supabase
      .from('drivers')
      .select('id, full_name')
      .eq('company_id', companyId)
      .eq('active', true)
      .order('full_name')
      .returns<{ id: string; full_name: string }[]>(),
  ]);
  for (const r of [trip, vehicles, drivers]) if (r.error) throw r.error;
  if (!trip.data || !['PLANNED', 'IN_PROGRESS'].includes(trip.data.status)) notFound();

  const data = trip.data;
  const locked = data.status === 'IN_PROGRESS';
  const route = [...data.trip_route_points].sort((a, b) => a.seq - b.seq).map((p) => p.name).join(' → ');

  return (
    <>
      <h1>{t('editTrip.title')}</h1>
      <p className="lead">
        {route} · <Link href={`/dispecerat/curse/${data.id}/opriri`}>{t('stops.link')}</Link>
      </p>
      {locked && <p className="alert alert-info">{t('editTrip.locked')}</p>}

      <div className="split">
        <ActionForm action={updateTrip} submitLabel={t('common.save')} pendingLabel={t('common.saving')}>
          <input type="hidden" name="id" value={data.id} />
          <input type="hidden" name="locked" value={String(locked)} />
          <fieldset>
            <legend>{t('editTrip.title')}</legend>
            <label>
              {t('trip.customTitle')}
              <input name="title" defaultValue={data.title} maxLength={80} disabled={locked} />
            </label>
            <div className="row">
              <label>
                {t('trip.vehicle')}
                <select name="vehicle_id" defaultValue={data.vehicle_id} disabled={locked}>
                  {(vehicles.data ?? []).map((v) => (
                    <option key={v.id} value={v.id}>
                      {v.label} · {v.seats}
                      {v.is_standby ? ` · ${t('standby')}` : ''}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                {t('trip.driver')}
                <select name="driver_id" defaultValue={data.driver_id ?? ''}>
                  <option value="">{t('trip.noDriver')}</option>
                  {(drivers.data ?? []).map((d) => (
                    <option key={d.id} value={d.id}>{d.full_name}</option>
                  ))}
                </select>
              </label>
            </div>
            <label>
              {t('trip.departure')}
              <input
                name="departure"
                type="datetime-local"
                defaultValue={utcToZonedLocal(data.departure_at, timeZone)}
                required
                disabled={locked}
              />
            </label>
          </fieldset>
        </ActionForm>

        {!locked && (
          <ActionForm
            action={cancelTrip}
            submitLabel={t('editTrip.cancelButton')}
            pendingLabel={t('common.saving')}
            className="form danger-zone"
          >
            <input type="hidden" name="id" value={data.id} />
            <fieldset>
              <legend>{t('editTrip.cancelTitle')}</legend>
              <p className="meta" style={{ margin: 0 }}>{t('editTrip.cancelHelp')}</p>
              <label className="check">
                <input type="checkbox" name="confirm" required />
                {t('editTrip.cancelConfirm')}
              </label>
            </fieldset>
          </ActionForm>
        )}
      </div>
    </>
  );
}
