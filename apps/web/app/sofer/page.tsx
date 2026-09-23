import Link from 'next/link';
import { redirect } from 'next/navigation';
import { ActionForm } from '../dispecerat/_components/action-form';
import { getT, type MessageKey } from '@/lib/i18n';
import { createClient } from '@/lib/supabase/server';
import { saveMyProfile } from './actions';

type DriverRow = {
  id: string; company_id: string; full_name: string; public_bio: string | null; photo_url: string | null;
  languages: string[]; driving_since: number | null; public_consent_at: string | null; profile_status: string;
  profile_note: string | null; companies: { name: string } | null;
};
const LANGS = ['ro', 'de', 'en', 'hu', 'ru', 'it'];

// Profilul șoferului, pe web. Aplicația mobilă va folosi aceeași funcție (update_my_driver_profile).
export default async function MyDriverProfilePage({ searchParams }: { searchParams: Promise<{ saved?: string }> }) {
  const { saved } = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login?next=/sofer');
  const { t } = await getT();
  const { data, error } = await supabase
    .from('drivers')
    .select('id, company_id, full_name, public_bio, photo_url, languages, driving_since, public_consent_at, profile_status, profile_note, companies(name)')
    .eq('user_id', user.id)
    .returns<DriverRow[]>();
  if (error) throw error;

  return (
    <main className="login">
      <div className="card" style={{ maxWidth: 640 }}>
        <h1>{t('me.title')}</h1>
        <p className="meta">{t('me.intro')}</p>
        {saved && <p className="alert alert-ok" role="status">{t('me.saved')}</p>}
        {(data ?? []).length === 0 && <p>{t('me.none')} <Link href="/invitatie">/invitatie</Link></p>}
        {(data ?? []).map((d) => (
          <section key={d.id} style={{ marginTop: 16 }}>
            <h2 className="h2">{d.companies?.name} · <span className={`badge badge-${d.profile_status}`}>{t(`drv.profile.${d.profile_status}` as MessageKey)}</span></h2>
            {d.profile_note && <p className="alert alert-info">{d.profile_note}</p>}
            {d.photo_url && <img src={d.photo_url} alt="" className="thumb round" />}
            <ActionForm action={saveMyProfile} submitLabel={t('me.save')} pendingLabel={t('common.saving')}>
              <input type="hidden" name="company_id" value={d.company_id} />
              <label>{t('site.photo')}<input name="photo" type="file" accept="image/jpeg,image/png,image/webp" /></label>
              <label>{t('site.bio')}<textarea name="bio" maxLength={600} rows={3} defaultValue={d.public_bio ?? ''} /></label>
              <fieldset className="inline-checks">
                <legend>{t('site.languages')}</legend>
                {LANGS.map((l) => (
                  <label key={l} className="check"><input type="checkbox" name="languages" value={l} defaultChecked={d.languages.includes(l)} />{l.toUpperCase()}</label>
                ))}
              </fieldset>
              <label>{t('site.drivingSince')}<input name="driving_since" type="number" min={1950} max={2100} defaultValue={d.driving_since ?? ''} /></label>
              <label className="check"><input type="checkbox" name="consent" defaultChecked={!!d.public_consent_at} />{t('me.consent')}</label>
            </ActionForm>
          </section>
        ))}
      </div>
    </main>
  );
}
