import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { deletePost } from '../actions';
import { PostForm } from '../post-form';

type Post = { id: string; title: string; excerpt: string | null; body: string; cover_url: string | null; published_at: string | null };

export default async function EditPostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, companyId } = await requireStaffCompany();
  const { t } = await getT();
  const { data, error } = await supabase
    .from('site_posts').select('id, title, excerpt, body, cover_url, published_at')
    .eq('id', id).eq('company_id', companyId).maybeSingle<Post>();
  if (error) throw error;
  if (!data) notFound();

  return (
    <>
      <h1>{t('posts.edit')}</h1>
      <p className="lead"><Link href="/dispecerat/site/stiri">← {t('posts.title')}</Link></p>
      <PostForm
        post={{ ...data, published: !!data.published_at }}
        labels={{
          headline: t('posts.headline'), excerpt: t('posts.excerpt'), body: t('posts.body'), cover: t('posts.cover'),
          publishNow: t('posts.publishNow'), save: t('posts.save'), saving: t('common.saving'), formatHelp: t('site.formatHelp'),
        }}
      />
      <form action={deletePost} style={{ marginTop: 24 }}>
        <input type="hidden" name="id" value={data.id} />
        <button className="btn btn-small">{t('posts.delete')}</button>
      </form>
    </>
  );
}
