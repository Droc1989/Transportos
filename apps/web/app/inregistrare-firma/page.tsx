import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getLandingCopy, getT } from '@/lib/i18n';
import { createClient } from '@/lib/supabase/server';
import { CompanyForm } from './company-form';

export default async function RegisterCompanyPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { t } = await getT();
  const { copy } = await getLandingCopy();

  if (user) {
    // Cine are deja o firmă (ca personal) merge direct în dispecerat.
    const { data } = await supabase.from('company_members').select('role').eq('user_id', user.id)
      .in('role', ['OWNER', 'ADMIN', 'DISPATCHER']).limit(1).maybeSingle();
    if (data) redirect('/dispecerat');
  }

  return (
    <main className="login">
      <div className="card" style={{ maxWidth: 640 }}>
        <h1>{t('reg.title')}</h1>
        <p className="meta">{t('reg.intro')}</p>
        <p className="alert alert-info">{copy.packages}</p>
        {!user ? (
          <>
            <p>{t('reg.needAccount')}</p>
            <p><Link className="btn btn-primary btn-link" href="/inregistrare?next=/inregistrare-firma">{t('reg.createAccount')}</Link></p>
            <p className="meta"><Link href="/login?next=/inregistrare-firma">{t('signup.have')}</Link></p>
          </>
        ) : (
          <CompanyForm
            rootHint={process.env.NEXT_PUBLIC_SITE_URL ?? ''}
            labels={{
              name: t('reg.name'), slug: t('reg.slug'), country: t('reg.country'), registrationNo: t('reg.registrationNo'),
              licenseNo: t('reg.licenseNo'), phone: t('reg.phone'), terms: t('reg.terms'), submit: t('reg.submit'),
              saving: t('common.saving'),
            }}
          />
        )}
        <p className="meta"><Link href="/invitatie">{t('reg.haveCode')}</Link></p>
      </div>
    </main>
  );
}
