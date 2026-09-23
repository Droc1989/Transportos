import { requireStaffCompany } from '@/lib/company';
import Link from 'next/link';
import { getT, type MessageKey } from '@/lib/i18n';
import { ActionForm } from '../_components/action-form';
import { addVehicle, setVehicleState } from './actions';

type Vehicle = {
  id: string;
  manufacture_year: number | null;
  approval_status: 'PENDING' | 'APPROVED' | 'REJECTED';
  label: string;
  plate: string | null;
  seats: number;
  status: string;
  is_standby: boolean;
};

export default async function VehiclesPage() {
  const { supabase, companyId } = await requireStaffCompany({ allowPending: true });
  const { t } = await getT();

  const { data, error } = await supabase
    .from('vehicles')
    .select('id, label, plate, seats, status, is_standby, manufacture_year, approval_status')
    .eq('company_id', companyId)
    .order('is_standby')
    .order('label')
    .returns<Vehicle[]>();
  if (error) throw error;
  const vehicles = data ?? [];

  return (
    <>
      <h1>{t('vehicles.title')}</h1>

      <div className="split">
        <section className="card">
          {vehicles.length === 0 ? (
            <p>{t('vehicles.empty')}</p>
          ) : (
            <table className="table">
              <thead>
                <tr>
                  <th>{t('vehicles.label')}</th>
                  <th>{t('vehicles.plate')}</th>
                  <th>{t('vehicles.seats')}</th>
                  <th>{t('veh.year')}</th>
                  <th>{t('vehicles.status')}</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {vehicles.map((v) => (
                  <tr key={v.id}>
                    <td className="plate">{v.label}</td>
                    <td>{v.plate ?? '—'}</td>
                    <td>{v.seats}</td>
                    <td>{v.manufacture_year ?? '—'}</td>
                    <td>
                      <span className={`badge badge-${v.approval_status}`}>{t(`veh.approval.${v.approval_status}` as MessageKey)}</span>
                      <div className="meta">{v.is_standby ? t('standby') : v.status}</div>
                      <Link href={`/dispecerat/vehicule/${v.id}`}>{t('veh.details')}</Link>
                    </td>
                    <td>
                      <div className="actions">
                        <form action={setVehicleState}>
                          <input type="hidden" name="id" value={v.id} />
                          <input type="hidden" name="to" value={v.is_standby ? 'AVAILABLE' : 'STANDBY'} />
                          <button className="btn btn-small">
                            {v.is_standby ? t('vehicles.makeActive') : t('vehicles.makeStandby')}
                          </button>
                        </form>
                        {!v.is_standby && (
                          <form action={setVehicleState}>
                            <input type="hidden" name="id" value={v.id} />
                            <input
                              type="hidden"
                              name="to"
                              value={v.status === 'MAINTENANCE' ? 'AVAILABLE' : 'MAINTENANCE'}
                            />
                            <button className="btn btn-small">
                              {v.status === 'MAINTENANCE' ? t('vehicles.toAvailable') : t('vehicles.toMaintenance')}
                            </button>
                          </form>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>

        <ActionForm action={addVehicle} submitLabel={t('vehicles.add')} pendingLabel={t('common.saving')}>
          <fieldset>
            <legend>{t('vehicles.add')}</legend>
            <div className="row">
              <label>
                {t('vehicles.label')}
                <input name="label" placeholder="TM-01" required maxLength={20} />
              </label>
              <label>
                {t('vehicles.seats')}
                <input name="seats" type="number" min={1} max={60} defaultValue={8} required />
              </label>
            </div>
            <div className="row">
              <label>
                {t('vehicles.plate')}
                <input name="plate" maxLength={15} required />
              </label>
              <label>
                {t('veh.year')}
                <input name="manufacture_year" type="number" min={1980} max={2100} required />
              </label>
            </div>
            <label className="check">
              <input type="checkbox" name="is_standby" />
              {t('vehicles.standby')}
            </label>
          </fieldset>
        </ActionForm>
      </div>
    </>
  );
}
