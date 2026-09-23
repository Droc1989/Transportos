import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { ActionForm } from '../_components/action-form';
import { addDriver, setDriverActive, unlinkDriver } from './actions';
import { InviteButton } from './invite-button';

type Driver = {
  id: string;
  full_name: string;
  phone: string | null;
  active: boolean;
  user_id: string | null;
};

export default async function DriversPage() {
  const { supabase, companyId, isAdmin } = await requireStaffCompany();
  const { t } = await getT();

  const { data, error } = await supabase
    .from('drivers')
    .select('id, full_name, phone, active, user_id')
    .eq('company_id', companyId)
    .order('active', { ascending: false })
    .order('full_name')
    .returns<Driver[]>();
  if (error) throw error;
  const drivers = data ?? [];

  return (
    <>
      <h1>{t('drivers.title')}</h1>
      {!isAdmin && <p className="alert alert-info">{t('drivers.adminOnly')}</p>}

      <div className="split">
        <section className="card">
          {drivers.length === 0 ? (
            <p>{t('drivers.empty')}</p>
          ) : (
            <table className="table">
              <thead>
                <tr>
                  <th>{t('drivers.name')}</th>
                  <th>{t('drivers.phone')}</th>
                  <th>{t('vehicles.status')}</th>
                  {isAdmin && <th />}
                </tr>
              </thead>
              <tbody>
                {drivers.map((d) => (
                  <tr key={d.id} className={d.active ? undefined : 'muted'}>
                    <td>
                      <strong>{d.full_name}</strong>
                      <div className="meta">{d.user_id ? t('drivers.hasAccount') : t('drivers.noAccount')}</div>
                    </td>
                    <td>{d.phone ?? '—'}</td>
                    <td>{d.active ? t('drivers.active') : t('drivers.inactive')}</td>
                    {isAdmin && (
                      <td>
                        <div className="actions">
                          {d.active && !d.user_id && (
                            <InviteButton
                              driverId={d.id}
                              phone={d.phone}
                              labels={{
                                button: t('invite.button'),
                                title: t('invite.title'),
                                help: t('invite.help'),
                                copy: t('invite.copy'),
                                copied: t('invite.copied'),
                                whatsapp: t('invite.whatsapp'),
                                message: t('invite.message'),
                              }}
                            />
                          )}
                          {d.user_id && (
                            <form action={unlinkDriver}>
                              <input type="hidden" name="id" value={d.id} />
                              <button className="btn btn-small">{t('invite.unlink')}</button>
                            </form>
                          )}
                          <form action={setDriverActive}>
                            <input type="hidden" name="id" value={d.id} />
                            <input type="hidden" name="active" value={d.active ? 'false' : 'true'} />
                            <button className="btn btn-small">
                              {d.active ? t('drivers.deactivate') : t('drivers.activate')}
                            </button>
                          </form>
                        </div>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>

        {isAdmin && (
          <ActionForm action={addDriver} submitLabel={t('drivers.add')} pendingLabel={t('common.saving')}>
            <fieldset>
              <legend>{t('drivers.add')}</legend>
              <label>
                {t('drivers.name')}
                <input name="full_name" required maxLength={80} />
              </label>
              <label>
                {t('drivers.phone')} ({t('common.optional')})
                <input name="phone" type="tel" maxLength={30} />
              </label>
            </fieldset>
          </ActionForm>
        )}
      </div>
    </>
  );
}
