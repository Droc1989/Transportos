import { requireStaffCompany } from '@/lib/company';
import { getT, type MessageKey } from '@/lib/i18n';
import { ActionForm } from '../_components/action-form';
import { addDriver, reviewDriverProfile, setDriverActive, unlinkDriver } from './actions';
import { InviteButton } from './invite-button';

type Driver = {
  id: string;
  full_name: string;
  phone: string | null;
  active: boolean;
  user_id: string | null;
  profile_status: string;
  public_bio: string | null;
  photo_url: string | null;
  public_consent_at: string | null;
};

export default async function DriversPage() {
  const { supabase, companyId, isAdmin } = await requireStaffCompany();
  const { t } = await getT();

  const { data, error } = await supabase
    .from('drivers')
    .select('id, full_name, phone, active, user_id, profile_status, public_bio, photo_url, public_consent_at')
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
                      <div className="meta">
                        {t('drv.profile')}: <span className={`badge badge-${d.profile_status}`}>{t(`drv.profile.${d.profile_status}` as MessageKey)}</span>
                        {d.public_consent_at ? ` · ${t('drv.consentYes')}` : ''}
                      </div>
                      {d.profile_status === 'SUBMITTED' && (
                        <div style={{ marginTop: 6 }}>
                          {d.photo_url && <img src={d.photo_url} alt="" className="thumb round" />}
                          {d.public_bio && <p className="meta" style={{ margin: '4px 0' }}>„{d.public_bio}”</p>}
                          {isAdmin && (
                            <div className="actions" style={{ justifyContent: 'flex-start' }}>
                              <form action={reviewDriverProfile}>
                                <input type="hidden" name="id" value={d.id} /><input type="hidden" name="approve" value="true" />
                                <button className="btn btn-small">{t('drv.approve')}</button>
                              </form>
                              <form action={reviewDriverProfile}>
                                <input type="hidden" name="id" value={d.id} /><input type="hidden" name="approve" value="false" />
                                <button className="btn btn-small">{t('drv.reject')}</button>
                              </form>
                            </div>
                          )}
                        </div>
                      )}
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
