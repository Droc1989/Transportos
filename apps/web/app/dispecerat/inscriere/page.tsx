import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { ActionForm } from '../_components/action-form';
import { submitForReview } from './actions';

type Check = {
  status: string;
  submitted_at: string | null;
  rejection_reason: string | null;
  company_data: boolean;
  terms: boolean;
  min_vehicle_year: number;
  has_complete_vehicle: boolean;
  ready: boolean;
  vehicles: {
    id: string; label: string; approval_status: string; has_year: boolean; below_min_year: boolean | null;
    has_exterior_photo: boolean; has_interior_photo: boolean; has_insurance: boolean; complete: boolean;
  }[];
};

function Mark({ ok }: { ok: boolean }) {
  return <span className={ok ? 'mark-ok' : 'mark-no'} aria-hidden="true">{ok ? '✓' : '○'}</span>;
}

export default async function RegistrationPage() {
  const { supabase, companyId, isActive, isAdmin } = await requireStaffCompany({ allowPending: true });
  if (isActive) redirect('/dispecerat');
  const { t } = await getT();
  const { data, error } = await supabase.rpc('get_registration_checklist', { p_company_id: companyId });
  if (error) throw error;
  const c = data as Check;
  const waiting = c.status === 'PENDING_VERIFICATION' && !!c.submitted_at;

  return (
    <>
      <h1>{t('onb.title')}</h1>
      {c.status === 'REJECTED' ? (
        <p className="alert alert-error">{t('onb.rejected')} {c.rejection_reason} {t('onb.fixAndResend')}</p>
      ) : waiting ? (
        <p className="alert alert-ok">{t('onb.submitted')}</p>
      ) : (
        <p className="alert alert-info">{t('onb.pending')}</p>
      )}

      <section className="card" style={{ marginBottom: 16 }}>
        <ul className="checklist">
          <li><Mark ok={c.company_data} /> {t('onb.companyData')}</li>
          <li><Mark ok={c.terms} /> {t('onb.terms')}</li>
          <li><Mark ok={c.has_complete_vehicle} /> {t('onb.vehicles')}</li>
        </ul>
        {c.vehicles.length > 0 && (
          <table className="table" style={{ marginTop: 12 }}>
            <tbody>
              {c.vehicles.map((v) => (
                <tr key={v.id}>
                  <td><Link href={`/dispecerat/vehicule/${v.id}`}><strong className="plate">{v.label}</strong></Link></td>
                  <td><Mark ok={v.has_year} /> {t('onb.year')}</td>
                  <td><Mark ok={v.has_exterior_photo} /> {t('onb.extPhoto')}</td>
                  <td><Mark ok={v.has_interior_photo} /> {t('onb.intPhoto')}</td>
                  <td><Mark ok={v.has_insurance} /> {t('onb.insurance')}</td>
                  <td className="meta">{v.below_min_year ? t('onb.old').replace('{year}', String(c.min_vehicle_year)) : ''}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <p style={{ marginBottom: 0 }}><Link href="/dispecerat/vehicule">{t('onb.addVehicles')} →</Link></p>
      </section>

      {isAdmin && !waiting && (
        <ActionForm action={submitForReview} submitLabel={t('onb.send')} pendingLabel={t('common.saving')}>
          <span />
        </ActionForm>
      )}
    </>
  );
}
