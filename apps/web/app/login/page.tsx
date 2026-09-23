import Link from 'next/link';
import { getT } from '@/lib/i18n';
import { LoginForm } from './login-form';
import { loginDestination } from '@/lib/login-destination';

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const { next, error } = await searchParams;
  const { t } = await getT();
  return (
    <main className="login">
      <div className="card">
        <h1>{t('login.title')}</h1>
        {error === 'no_company' && <p className="alert alert-error">{t('login.noCompany')}</p>}
        <LoginForm
          next={loginDestination(next)}
          labels={{
            email: t('login.email'),
            password: t('login.password'),
            submit: t('login.submit'),
            error: t('login.error'),
          }}
        />
        <p>
          <Link href={`/inregistrare?next=${encodeURIComponent(next ?? '/invitatie')}`}>{t('signup.need')}</Link>
        </p>
      </div>
    </main>
  );
}
