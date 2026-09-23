import Link from 'next/link';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { setPostPublished } from './actions';
import { PostForm } from './post-form';

type Post = { id: string; title: string; slug: string; published_at: string | null; updated_at: string };

export default async function PostsPage() {
  const { supabase, companyId, timeZone } = await requireStaffCompany();
  const { t, locale } = await getT();
  const { data, error } = await supabase
    .from('site_posts').select('id, title, slug, published_at, updated_at')
    .eq('company_id', companyId).order('updated_at', { ascending: false }).returns<Post[]>();
  if (error) throw error;
  const fmt = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', { timeZone, dateStyle: 'medium' });

  return (
    <>
      <h1>{t('posts.title')}</h1>
      <p className="lead"><Link href="/dispecerat/site">← {t('site.title')}</Link></p>
      <div className="split">
        <section className="card">
          {(data ?? []).length === 0 ? <p>{t('posts.empty')}</p> : (
            <table className="table">
              <tbody>
                {(data ?? []).map((p) => (
                  <tr key={p.id}>
                    <td>
                      <Link href={`/dispecerat/site/stiri/${p.id}`}><strong>{p.title}</strong></Link>
                      <div className="meta">
                        {p.published_at ? `${t('posts.published')} · ${fmt.format(new Date(p.published_at))}` : t('posts.draft')}
                      </div>
                    </td>
                    <td>
                      <form action={setPostPublished}>
                        <input type="hidden" name="id" value={p.id} />
                        <input type="hidden" name="publish" value={p.published_at ? 'false' : 'true'} />
                        <button className="btn btn-small">{p.published_at ? t('posts.unpublish') : t('posts.publish')}</button>
                      </form>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
        <div>
          <h2 className="h2">{t('posts.new')}</h2>
          <PostForm labels={{
            headline: t('posts.headline'), excerpt: t('posts.excerpt'), body: t('posts.body'), cover: t('posts.cover'),
            publishNow: t('posts.publishNow'), save: t('posts.save'), saving: t('common.saving'), formatHelp: t('site.formatHelp'),
          }} />
        </div>
      </div>
    </>
  );
}
