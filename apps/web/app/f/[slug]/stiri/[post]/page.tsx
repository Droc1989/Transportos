import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { RichText, plainText } from '@/lib/rich-text';
import { getSite, getSitePost, siteBase, siteLang, siteText } from '@/lib/site';

type Params = { params: Promise<{ slug: string; post: string }> };

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { slug, post } = await params;
  const [site, article] = await Promise.all([getSite(slug), getSitePost(slug, post)]);
  if (!site || !article) return {};
  const description = article.excerpt ?? plainText(article.body);
  return {
    title: `${article.title} – ${site.name}`,
    description,
    openGraph: { title: article.title, description, type: 'article', publishedTime: article.published_at,
                 images: article.cover_url ? [article.cover_url] : undefined },
  };
}

export default async function SiteArticle({ params }: Params) {
  const { slug, post } = await params;
  const [site, article] = await Promise.all([getSite(slug), getSitePost(slug, post)]);
  if (!site || !article) notFound();
  const lang = siteLang(site);
  const t = siteText[lang];
  const base = await siteBase(slug);
  const date = new Intl.DateTimeFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { dateStyle: 'long' });
  return (
    <main className="site-section site-prose">
      <p><Link href={`${base}/stiri`}>← {t.back}</Link></p>
      <h1>{article.title}</h1>
      <div className="meta">{date.format(new Date(article.published_at))}</div>
      {article.cover_url && <img src={article.cover_url} alt="" className="site-cover" />}
      {article.excerpt && <p className="site-lead">{article.excerpt}</p>}
      <RichText text={article.body} />
    </main>
  );
}
