import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { ActionForm } from '../_components/action-form';
import { addVehicle, setVehicleState } from './actions';

type Vehicle = {
  id: string;
  label: string;
  plate: string | null;
  seats: number;
  status: string;
  is_standby: boolean;
};

export default async function VehiclesPage() {
  const { supabase, companyId } = await requireStaffCompany();
  const { t } = await getT();

  const { data, error } = await supabase
    .from('vehicles')
    .select('id, label, plate, seats, status, is_standby')
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
                    <td>{v.is_standby ? t('standby') : v.status}</td>
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
            <label>
              {t('vehicles.plate')} ({t('common.optional')})
              <input name="plate" maxLength={15} />
            </label>
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
