import Link from 'next/link';
import { notFound } from 'next/navigation';
import { FEATURE_LABELS, VEHICLE_FEATURES, VEHICLE_PHOTO_KINDS } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { getT, type MessageKey } from '@/lib/i18n';
import { ActionForm } from '../../_components/action-form';
import { declareInsurance, deleteVehiclePhoto, saveVehicleDetails, uploadVehiclePhotos } from './actions';

type Vehicle = {
  id: string; label: string; plate: string | null; seats: number; manufacture_year: number | null; features: string[];
  luggage_pieces: number | null; luggage_kg: number | null; public_description: string | null;
  rca_valid_until: string | null; passenger_insurance_until: string | null; insurance_declared_at: string | null;
  approval_status: 'PENDING' | 'APPROVED' | 'REJECTED'; approval_note: string | null;
};
type Photo = { id: string; kind: string; url: string };

export default async function VehicleDetailPage({ params, searchParams }: {
  params: Promise<{ id: string }>; searchParams: Promise<{ saved?: string }>;
}) {
  const { id } = await params;
  const { saved } = await searchParams;
  const { supabase, companyId, timeZone } = await requireStaffCompany({ allowPending: true });
  const { t, locale } = await getT();

  const [vehicle, photos] = await Promise.all([
    supabase.from('vehicles').select('id, label, plate, seats, manufacture_year, features, luggage_pieces, luggage_kg, public_description, rca_valid_until, passenger_insurance_until, insurance_declared_at, approval_status, approval_note')
      .eq('id', id).eq('company_id', companyId).maybeSingle<Vehicle>(),
    supabase.from('vehicle_photos').select('id, kind, url').eq('vehicle_id', id).order('kind').order('sort').returns<Photo[]>(),
  ]);
  if (vehicle.error) throw vehicle.error;
  if (photos.error) throw photos.error;
  if (!vehicle.data) notFound();
  const v = vehicle.data;
  const labels = FEATURE_LABELS[locale === 'de' ? 'de' : 'ro'];
  const fmt = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', { timeZone, dateStyle: 'medium', timeStyle: 'short' });

  return (
    <>
      <h1>{t('veh.edit')} <span className="plate">{v.label}</span>{' '}
        <span className={`badge badge-${v.approval_status}`}>{t(`veh.approval.${v.approval_status}` as MessageKey)}</span>
      </h1>
      <p className="lead"><Link href="/dispecerat/vehicule">← {t('vehicles.title')}</Link> · <Link href="/dispecerat/inscriere">{t('onb.title')}</Link></p>
      {saved && <p className="alert alert-ok" role="status">{t('site.saved')}</p>}
      {v.approval_note && <p className="alert alert-info">{t('veh.note')}: {v.approval_note}</p>}

      <div className="split">
        <ActionForm action={saveVehicleDetails} submitLabel={t('common.save')} pendingLabel={t('common.saving')}>
          <input type="hidden" name="id" value={v.id} />
          <fieldset>
            <legend>{t('veh.edit')}</legend>
            <div className="row">
              <label>{t('vehicles.label')}<input name="label" required maxLength={20} defaultValue={v.label} /></label>
              <label>{t('vehicles.plate')}<input name="plate" required maxLength={15} defaultValue={v.plate ?? ''} /></label>
            </div>
            <div className="row">
              <label>{t('vehicles.seats')}<input name="seats" type="number" min={1} max={60} required defaultValue={v.seats} /></label>
              <label>{t('veh.year')}<input name="manufacture_year" type="number" min={1980} max={2100} required defaultValue={v.manufacture_year ?? ''} /></label>
            </div>
            <p className="meta" style={{ margin: 0 }}>{t('veh.reapproval')}</p>
            <fieldset className="inline-checks">
              <legend>{t('veh.features')}</legend>
              {VEHICLE_FEATURES.map((f) => (
                <label key={f} className="check"><input type="checkbox" name="features" value={f} defaultChecked={v.features.includes(f)} />{labels[f]}</label>
              ))}
            </fieldset>
            <div className="row">
              <label>{t('veh.luggagePieces')}<input name="luggage_pieces" type="number" min={0} max={10} defaultValue={v.luggage_pieces ?? ''} /></label>
              <label>{t('veh.luggageKg')}<input name="luggage_kg" type="number" min={0} max={200} defaultValue={v.luggage_kg ?? ''} /></label>
            </div>
            <label>{t('veh.description')}<textarea name="public_description" maxLength={500} rows={3} defaultValue={v.public_description ?? ''} /></label>
          </fieldset>
        </ActionForm>

        <div className="list">
          <section className="card">
            <h2 className="h2">{t('veh.photos')}</h2>
            <p className="meta">{t('veh.photosHelp')}</p>
            {(photos.data ?? []).length > 0 && (
              <div className="photo-grid" style={{ marginBottom: 12 }}>
                {(photos.data ?? []).map((p) => (
                  <figure key={p.id}>
                    <img src={p.url} alt={t(`veh.kind.${p.kind}` as MessageKey)} />
                    <figcaption className="meta">{t(`veh.kind.${p.kind}` as MessageKey)}</figcaption>
                    <form action={deleteVehiclePhoto}>
                      <input type="hidden" name="id" value={v.id} /><input type="hidden" name="photo_id" value={p.id} />
                      <button className="btn btn-small">{t('veh.deletePhoto')}</button>
                    </form>
                  </figure>
                ))}
              </div>
            )}
            <ActionForm action={uploadVehiclePhotos} submitLabel={t('veh.upload')} pendingLabel={t('common.saving')}>
              <input type="hidden" name="id" value={v.id} />
              <label>{t('veh.photoKind')}
                <select name="kind" defaultValue="EXTERIOR">
                  {VEHICLE_PHOTO_KINDS.map((k) => <option key={k} value={k}>{t(`veh.kind.${k}` as MessageKey)}</option>)}
                </select>
              </label>
              <input name="photos" type="file" accept="image/jpeg,image/png,image/webp" multiple required />
            </ActionForm>
          </section>

          <section className="card">
            <h2 className="h2">{t('veh.insurance')}</h2>
            {v.insurance_declared_at && (
              <p className="meta">{t('veh.declaredAt')}: {fmt.format(new Date(v.insurance_declared_at))}</p>
            )}
            <ActionForm action={declareInsurance} submitLabel={t('veh.declare')} pendingLabel={t('common.saving')}>
              <input type="hidden" name="id" value={v.id} />
              <div className="row">
                <label>{t('veh.rcaUntil')}<input name="rca_valid_until" type="date" required defaultValue={v.rca_valid_until ?? ''} /></label>
                <label>{t('veh.passengerUntil')}<input name="passenger_insurance_until" type="date" required defaultValue={v.passenger_insurance_until ?? ''} /></label>
              </div>
              <label className="check"><input type="checkbox" name="confirm" required />{t('veh.insuranceConfirm')}</label>
            </ActionForm>
          </section>
        </div>
      </div>
    </>
  );
}
