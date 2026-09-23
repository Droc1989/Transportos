import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { ActionForm } from '../../_components/action-form';
import { createTrips } from './actions';

type Option = { id: string; name: string };
type VehicleOption = { id: string; label: string; seats: number; is_standby: boolean; status: string };

export default async function NewTripPage() {
  const { supabase, companyId } = await requireStaffCompany();
  const { t } = await getT();

  const [templates, vehicles, drivers] = await Promise.all([
    supabase.from('route_templates').select('id, name').eq('company_id', companyId).order('name').returns<Option[]>(),
    supabase
      .from('vehicles')
      .select('id, label, seats, is_standby, status')
      .eq('company_id', companyId)
      .order('is_standby')
      .order('label')
      .returns<VehicleOption[]>(),
    supabase
      .from('drivers')
      .select('id, name:full_name')
      .eq('company_id', companyId)
      .eq('active', true)
      .order('full_name')
      .returns<Option[]>(),
  ]);
  for (const r of [templates, vehicles, drivers]) if (r.error) throw r.error;

  const routeList = templates.data ?? [];
  const vehicleList = vehicles.data ?? [];

  return (
    <>
      <h1>{t('trip.title')}</h1>
      {routeList.length === 0 ? (
        <p className="card">{t('trip.needRoute')}</p>
      ) : vehicleList.length === 0 ? (
        <p className="card">{t('trip.needVehicle')}</p>
      ) : (
        <ActionForm action={createTrips} submitLabel={t('trip.create')} pendingLabel={t('common.saving')}>
          <fieldset>
            <legend>{t('trip.title')}</legend>
            <label>
              {t('trip.route')}
              <select name="template_id" required>
                {routeList.map((r) => (
                  <option key={r.id} value={r.id}>{r.name}</option>
                ))}
              </select>
            </label>
            <div className="row">
              <label>
                {t('trip.vehicle')}
                <select name="vehicle_id" required>
                  {vehicleList.map((v) => (
                    <option key={v.id} value={v.id}>
                      {v.label} · {v.seats}
                      {v.is_standby ? ` · ${t('standby')}` : ''}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                {t('trip.driver')}
                <select name="driver_id" defaultValue="">
                  <option value="">{t('trip.noDriver')}</option>
                  {(drivers.data ?? []).map((d) => (
                    <option key={d.id} value={d.id}>{d.name}</option>
                  ))}
                </select>
              </label>
            </div>
            <div className="row">
              <label>
                {t('trip.departure')}
                <input name="departure" type="datetime-local" required />
              </label>
              <label>
                {t('trip.repeat')}
                <input name="weeks" type="number" min={1} max={12} defaultValue={1} aria-describedby="weeks-hint" />
              </label>
            </div>
            <p id="weeks-hint" className="meta" style={{ margin: 0 }}>{t('trip.repeatHint')}</p>
            <label>
              {t('trip.customTitle')} ({t('common.optional')})
              <input name="title" maxLength={80} />
            </label>
          </fieldset>
        </ActionForm>
      )}
    </>
  );
}
