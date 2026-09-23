import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { utcToZonedLocal } from '@/lib/time';

export default async function ExportPage() {
  const { timeZone } = await requireStaffCompany();
  const { t } = await getT();
  const today = utcToZonedLocal(new Date().toISOString(), timeZone).slice(0, 10);
  const monthStart = `${today.slice(0, 8)}01`;
  return (
    <>
      <h1>{t('export.title')}</h1>
      <p className="lead">{t('export.help')}</p>
      <form action="/dispecerat/export/csv" method="get" className="form">
        <fieldset>
          <legend>{t('export.title')}</legend>
          <div className="row">
            <label>
              {t('export.from')}
              <input type="date" name="from" defaultValue={monthStart} required />
            </label>
            <label>
              {t('export.to')}
              <input type="date" name="to" defaultValue={today} required />
            </label>
          </div>
        </fieldset>
        <button className="btn btn-primary">{t('export.download')}</button>
      </form>
    </>
  );
}
