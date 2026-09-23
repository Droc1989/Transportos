import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { ShareButton } from '../_components/share-button';
import { createStaffInvite } from './actions';

export default async function TeamPage() {
  const { isAdmin, role } = await requireStaffCompany();
  const { t } = await getT();
  const roles = role === 'OWNER' ? (['DISPATCHER', 'ADMIN', 'OWNER'] as const) : (['DISPATCHER', 'ADMIN'] as const);

  return (
    <>
      <h1>{t('team.title')}</h1>
      <p className="lead">{t('team.help')}</p>
      {!isAdmin ? (
        <p className="alert alert-info">{t('team.adminOnly')}</p>
      ) : (
        <div className="list">
          {roles.map((r) => (
            <div key={r} className="card trip">
              <strong>{t(`team.${r}`)}</strong>
              <ShareButton
                action={createStaffInvite}
                fields={{ role: r }}
                mono
                labels={{
                  button: t('team.invite'),
                  title: t('invite.title'),
                  help: t('invite.help'),
                  copy: t('invite.copy'),
                  copied: t('invite.copied'),
                  whatsapp: t('invite.whatsapp'),
                  message: t('team.message'),
                }}
              />
            </div>
          ))}
        </div>
      )}
    </>
  );
}
