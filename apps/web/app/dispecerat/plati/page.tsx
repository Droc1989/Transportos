import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { stripeConfigured } from '@/lib/stripe';
import { ActionForm } from '../_components/action-form';
import { connectStripe, savePaymentSettings } from './actions';

type Settings = {
  accepts_full: boolean; accepts_deposit: boolean; deposit_percent: number; accepts_cash: boolean;
  cancel_until_hours: number; stripe_account_id: string | null; stripe_charges_enabled: boolean;
};

export default async function PaymentsPage() {
  const { supabase, companyId, isAdmin } = await requireStaffCompany();
  const { t } = await getT();
  const { data, error } = await supabase.from('company_payment_settings').select('*').eq('company_id', companyId).maybeSingle<Settings>();
  if (error) throw error;
  const s = data;
  const status = s?.stripe_charges_enabled ? 'connected' : s?.stripe_account_id ? 'pending' : 'none';

  return (
    <>
      <h1>{t('pay.title')}</h1>
      <p className="lead">{t('pay.intro')}</p>
      <section className="card" style={{ marginBottom: 16 }}>
        <p className={`alert ${status === 'connected' ? 'alert-ok' : 'alert-info'}`} style={{ marginTop: 0 }}>
          {status === 'connected' ? t('pay.connected') : status === 'pending' ? t('pay.pending') : t('pay.notConnected')}
        </p>
        {!stripeConfigured() ? (
          <p className="meta">{t('pay.notConfigured')}</p>
        ) : isAdmin && status !== 'connected' ? (
          <form action={connectStripe}>
            <button className="btn btn-primary">{status === 'pending' ? t('pay.continue') : t('pay.connect')}</button>
          </form>
        ) : null}
      </section>
      {isAdmin ? (
        <ActionForm action={savePaymentSettings} submitLabel={t('common.save')} pendingLabel={t('common.saving')}>
          <fieldset>
            <legend>{t('pay.options')}</legend>
            <label className="check"><input type="checkbox" name="accepts_full" defaultChecked={s?.accepts_full ?? true} />{t('pay.full')}</label>
            <label className="check"><input type="checkbox" name="accepts_deposit" defaultChecked={s?.accepts_deposit ?? true} />{t('pay.deposit')}</label>
            <label>{t('pay.depositPercent')}<input name="deposit_percent" type="number" min={5} max={100} defaultValue={s?.deposit_percent ?? 20} /></label>
            <label className="check"><input type="checkbox" name="accepts_cash" defaultChecked={s?.accepts_cash ?? true} />{t('pay.cash')}</label>
            <label>{t('pay.cancelHours')}<input name="cancel_until_hours" type="number" min={0} max={720} defaultValue={s?.cancel_until_hours ?? 24} /></label>
          </fieldset>
        </ActionForm>
      ) : (
        <p className="alert alert-info">{t('site.adminOnly')}</p>
      )}
    </>
  );
}
