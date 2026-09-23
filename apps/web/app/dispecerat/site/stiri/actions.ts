'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { getT } from '@/lib/i18n';
import { slugify } from '@/lib/slug';
import { uploadSiteImage } from '@/lib/upload';

async function uniqueSlug(supabase: Awaited<ReturnType<typeof requireStaffCompany>>['supabase'], companyId: string, title: string, exceptId?: string) {
  const base = slugify(title) || 'stire';
  for (let i = 1; i < 50; i += 1) {
    const candidate = i === 1 ? base : `${base}-${i}`;
    let q = supabase.from('site_posts').select('id').eq('company_id', companyId).eq('slug', candidate);
    if (exceptId) q = q.neq('id', exceptId);
    const { data } = await q.maybeSingle();
    if (!data) return candidate;
  }
  return `${base}-${Date.now()}`;
}

function refresh() {
  revalidatePath('/dispecerat/site/stiri');
  revalidatePath('/f', 'layout');
}

export async function savePost(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, companyId } = await requireStaffCompany();
  const id = text(form, 'id');
  const title = text(form, 'title');
  if (title.length < 3) {
    const { locale } = await getT();
    return { error: locale === 'de' ? 'Der Titel ist zu kurz.' : 'Titlul e prea scurt.' };
  }
  let cover: string | null;
  try {
    cover = await uploadSiteImage(supabase, companyId, form.get('cover'), 'posts');
  } catch (e) {
    const { t } = await getT();
    return { error: (e as Error).message.startsWith('IMAGE_') ? t('site.imageError') : await errorMessage(e as { message?: string }) };
  }
  const row: Record<string, unknown> = {
    company_id: companyId,
    title,
    excerpt: text(form, 'excerpt') || null,
    body: text(form, 'body'),
  };
  if (cover) row.cover_url = cover;
  if (form.get('publish_now') === 'on') row.published_at = new Date().toISOString();

  const { error } = id
    ? await supabase.from('site_posts').update(row).eq('id', id)
    : await supabase.from('site_posts').insert({ ...row, slug: await uniqueSlug(supabase, companyId, title) });
  if (error) return { error: await errorMessage(error) };
  refresh();
  redirect('/dispecerat/site/stiri');
}

export async function setPostPublished(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const publish = text(form, 'publish') === 'true';
  const { error } = await supabase
    .from('site_posts')
    .update({ published_at: publish ? new Date().toISOString() : null })
    .eq('id', text(form, 'id'));
  if (error) throw error;
  refresh();
}

export async function deletePost(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const { error } = await supabase.from('site_posts').delete().eq('id', text(form, 'id'));
  if (error) throw error;
  refresh();
  redirect('/dispecerat/site/stiri');
}
