import { redirect } from 'next/navigation';
import { getT } from '@/lib/i18n';
import { createClient } from '@/lib/supabase/server';
import { AcceptForm } from './accept-form';

export default async function InvitePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/inregistrare?next=/invitatie');

  const { t } = await getT();
  return (
    <main className="login">
      <div className="card">
        <h1>{t('accept.title')}</h1>
        <AcceptForm
          labels={{
            code: t('accept.code'),
            submit: t('accept.submit'),
            done: t('accept.done'),
            next: t('accept.next'),
            doneStaff: t('accept.doneStaff'),
            openDispatch: t('accept.openDispatch'),
          }}
        />
      </div>
    </main>
  );
}
