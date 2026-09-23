'use server';

import { redirect } from 'next/navigation';
import { errorMessage, text, type FormState } from '@/lib/form';
import { getT } from '@/lib/i18n';
import { createClient } from '@/lib/supabase/server';
import { uploadSiteImage } from '@/lib/upload';

export async function saveMyProfile(_prev: FormState, form: FormData): Promise<FormState> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login?next=/sofer');
  const companyId = text(form, 'company_id');
  let photo: string | null = null;
  try {
    // Poza merge în folderul șoferului: <firmă>/drivers/<cont>/… (politica din migrația 2300)
    photo = await uploadSiteImage(supabase, companyId, form.get('photo'), 'drivers', user.id);
  } catch (e) {
    const { t } = await getT();
    return { error: (e as Error).message.startsWith('IMAGE_') ? t('site.imageError') : await errorMessage(e as { message?: string }) };
  }
  const since = Number(text(form, 'driving_since'));
  const { error } = await supabase.rpc('update_my_driver_profile', {
    p_company_id: companyId,
    p_bio: text(form, 'bio') || null,
    p_languages: form.getAll('languages').map(String),
    p_driving_since: Number.isInteger(since) && since > 1950 ? since : null,
    p_photo_url: photo,
    p_public_consent: form.get('consent') === 'on',
  });
  if (error) return { error: await errorMessage(error) };
  redirect('/sofer?saved=1');
}
