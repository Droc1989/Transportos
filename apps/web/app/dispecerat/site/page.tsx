import Link from 'next/link';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { ActionForm } from '../_components/action-form';
import { saveDriverSite, saveRouteSite, saveSite, saveVehicleSite } from './actions';

type Site = {
  published: boolean; tagline: string | null; about: string | null; phone: string | null; whatsapp: string | null;
  email: string | null; address: string | null; logo_url: string | null; cover_url: string | null;
  accent_color: string; seo_description: string | null; custom_domain: string | null;
};
type RouteRow = { id: string; name: string; show_on_site: boolean; public_note: string | null; price_from_cents: number | null };
type VehicleRow = { id: string; label: string; seats: number; show_on_site: boolean; public_description: string | null; photo_url: string | null; amenities: string[] };
type DriverRow = { id: string; full_name: string; public_profile: boolean; public_bio: string | null; photo_url: string | null;
  languages: string[]; driving_since: number | null; public_consent_at: string | null };

const LANGS = ['ro', 'de', 'en', 'hu', 'ru', 'it'];

export default async function SiteEditorPage({ searchParams }: { searchParams: Promise<{ saved?: string; error?: string }> }) {
  const { saved, error } = await searchParams;
  const { supabase, companyId, isAdmin } = await requireStaffCompany();
  const { t } = await getT();

  const [company, site, routes, vehicles, drivers] = await Promise.all([
    supabase.from('companies').select('slug').eq('id', companyId).single<{ slug: string }>(),
    supabase.from('company_sites').select('*').eq('company_id', companyId).maybeSingle<Site>(),
    supabase.from('route_templates').select('id, name, show_on_site, public_note, price_from_cents').eq('company_id', companyId).order('name').returns<RouteRow[]>(),
    supabase.from('vehicles').select('id, label, seats, show_on_site, public_description, photo_url, amenities').eq('company_id', companyId).order('label').returns<VehicleRow[]>(),
    supabase.from('drivers').select('id, full_name, public_profile, public_bio, photo_url, languages, driving_since, public_consent_at').eq('company_id', companyId).eq('active', true).order('full_name').returns<DriverRow[]>(),
  ]);
  for (const r of [company, site, routes, vehicles, drivers]) if (r.error) throw r.error;

  const slug = company.data!.slug;
  const s = site.data;
  const root = process.env.NEXT_PUBLIC_ROOT_DOMAIN;
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? '';
  const addresses = [
    `${siteUrl}/f/${slug}`,
    root ? `https://${slug}.${root}` : null,
    s?.custom_domain ? `https://${s.custom_domain}` : null,
  ].filter(Boolean) as string[];

  return (
    <>
      <h1>{t('site.title')}</h1>
      <p className="lead">{t('site.intro')} <Link href="/dispecerat/site/stiri">{t('posts.title')} →</Link></p>
      {saved && <p className="alert alert-ok" role="status">{t('site.saved')}</p>}
      {error && <p className="alert alert-error" role="alert">{error}</p>}

      <section className="card" style={{ marginBottom: 16 }}>
        <h2 className="h2">{t('site.addresses')}</h2>
        {s?.published ? (
          <ul className="meta" style={{ margin: 0, paddingLeft: 18 }}>
            {addresses.map((a) => <li key={a}><a href={a} target="_blank" rel="noreferrer">{a}</a></li>)}
          </ul>
        ) : (
          <p className="meta" style={{ margin: 0 }}>{t('site.notPublished')}</p>
        )}
      </section>

      {!isAdmin ? (
        <p className="alert alert-info">{t('site.adminOnly')}</p>
      ) : (
        <>
          <ActionForm action={saveSite} submitLabel={t('site.save')} pendingLabel={t('common.saving')}>
            <fieldset>
              <legend>{t('site.title')}</legend>
              <label className="check"><input type="checkbox" name="published" defaultChecked={s?.published ?? false} />{t('site.published')}</label>
              <label>{t('site.tagline')}<input name="tagline" maxLength={160} defaultValue={s?.tagline ?? ''} /></label>
              <label>
                {t('site.about')}
                <textarea name="about" maxLength={8000} rows={8} defaultValue={s?.about ?? ''} />
                <span className="meta" style={{ fontWeight: 400 }}>{t('site.formatHelp')}</span>
              </label>
              <div className="row">
                <label>{t('site.phone')}<input name="phone" type="tel" maxLength={40} defaultValue={s?.phone ?? ''} /></label>
                <label>{t('site.whatsapp')}<input name="whatsapp" type="tel" maxLength={40} defaultValue={s?.whatsapp ?? ''} /></label>
              </div>
              <div className="row">
                <label>{t('site.email')}<input name="email" type="email" maxLength={120} defaultValue={s?.email ?? ''} /></label>
                <label>{t('site.color')}<input name="accent_color" type="color" defaultValue={s?.accent_color ?? '#0B4EA2'} /></label>
              </div>
              <label>{t('site.address')}<input name="address" maxLength={300} defaultValue={s?.address ?? ''} /></label>
              <div className="row">
                <label>{t('site.logo')}<input name="logo" type="file" accept="image/jpeg,image/png,image/webp" /></label>
                <label>{t('site.cover')}<input name="cover" type="file" accept="image/jpeg,image/png,image/webp" /></label>
              </div>
              <label>{t('site.seo')}<input name="seo_description" maxLength={300} defaultValue={s?.seo_description ?? ''} /></label>
              <label>
                {t('site.domain')}
                <input name="custom_domain" maxLength={120} defaultValue={s?.custom_domain ?? ''} />
                <span className="meta" style={{ fontWeight: 400 }}>{t('site.domainHelp')}</span>
              </label>
            </fieldset>
          </ActionForm>

          <section className="card" style={{ marginTop: 16 }}>
            <h2 className="h2">{t('site.routes')}</h2>
            <div className="list">
              {(routes.data ?? []).map((r) => (
                <form key={r.id} action={saveRouteSite} className="site-row">
                  <input type="hidden" name="id" value={r.id} />
                  <strong>{r.name}</strong>
                  <label className="check"><input type="checkbox" name="show_on_site" defaultChecked={r.show_on_site} />{t('site.showOnSite')}</label>
                  <label>{t('site.routeNote')}<input name="public_note" maxLength={200} defaultValue={r.public_note ?? ''} /></label>
                  <label>{t('site.priceFrom')}<input name="price_from" inputMode="decimal" defaultValue={r.price_from_cents !== null ? String(r.price_from_cents / 100) : ''} /></label>
                  <button className="btn btn-small">{t('site.saveRow')}</button>
                </form>
              ))}
            </div>
          </section>

          <section className="card" style={{ marginTop: 16 }}>
            <h2 className="h2">{t('site.fleet')}</h2>
            <div className="list">
              {(vehicles.data ?? []).map((v) => (
                <form key={v.id} action={saveVehicleSite} className="site-row">
                  <input type="hidden" name="id" value={v.id} />
                  <strong>{v.label} · {v.seats}</strong>
                  {v.photo_url && <img src={v.photo_url} alt="" className="thumb" />}
                  <label className="check"><input type="checkbox" name="show_on_site" defaultChecked={v.show_on_site} />{t('site.showOnSite')}</label>
                  <label>{t('site.about')}<input name="public_description" maxLength={500} defaultValue={v.public_description ?? ''} /></label>
                  <label>{t('site.amenities')}<input name="amenities" defaultValue={v.amenities.join(', ')} /></label>
                  <label>{t('site.photo')}<input name="photo" type="file" accept="image/jpeg,image/png,image/webp" /></label>
                  <button className="btn btn-small">{t('site.saveRow')}</button>
                </form>
              ))}
            </div>
          </section>

          <section className="card" style={{ marginTop: 16 }}>
            <h2 className="h2">{t('site.drivers')}</h2>
            <p className="meta">{t('site.driversHelp')}</p>
            <div className="list">
              {(drivers.data ?? []).map((d) => (
                <form key={d.id} action={saveDriverSite} className="site-row">
                  <input type="hidden" name="id" value={d.id} />
                  <strong>{d.full_name}</strong>
                  {d.photo_url && <img src={d.photo_url} alt="" className="thumb round" />}
                  <label className="check"><input type="checkbox" name="consent" defaultChecked={!!d.public_consent_at} />{t('site.consent')}</label>
                  <label className="check"><input type="checkbox" name="public_profile" defaultChecked={d.public_profile} />{t('site.showOnSite')}</label>
                  <label>{t('site.bio')}<textarea name="bio" maxLength={600} rows={2} defaultValue={d.public_bio ?? ''} /></label>
                  <fieldset className="inline-checks">
                    <legend>{t('site.languages')}</legend>
                    {LANGS.map((l) => (
                      <label key={l} className="check"><input type="checkbox" name="languages" value={l} defaultChecked={d.languages.includes(l)} />{l.toUpperCase()}</label>
                    ))}
                  </fieldset>
                  <label>{t('site.drivingSince')}<input name="driving_since" type="number" min={1950} max={2100} defaultValue={d.driving_since ?? ''} /></label>
                  <label>{t('site.photo')}<input name="photo" type="file" accept="image/jpeg,image/png,image/webp" /></label>
                  <button className="btn btn-small">{t('site.saveRow')}</button>
                </form>
              ))}
            </div>
          </section>
        </>
      )}
    </>
  );
}
