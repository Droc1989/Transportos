import Link from 'next/link';
import { getT } from '@/lib/i18n';
import { SignUpForm } from './signup-form';

export default async function SignUpPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const { next = '/invitatie' } = await searchParams;
  const { t } = await getT();
  return (
    <main className="login">
      <div className="card">
        <h1>{t('signup.title')}</h1>
        <SignUpForm
          next={next}
          labels={{
            email: t('login.email'),
            password: t('login.password'),
            submit: t('signup.submit'),
            error: t('signup.error'),
            check: t('signup.check'),
          }}
        />
        <p><Link href={`/login?next=${encodeURIComponent(next)}`}>{t('signup.have')}</Link></p>
      </div>
    </main>
  );
}
