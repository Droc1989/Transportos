import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getSite, siteBase, siteLang, siteText } from '@/lib/site';

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const site = await getSite(slug);
  return site ? { title: `${siteText[siteLang(site)].news} – ${site.name}` } : {};
}

export default async function SiteNews({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const site = await getSite(slug);
  if (!site) notFound();
  const lang = siteLang(site);
  const t = siteText[lang];
  const base = await siteBase(slug);
  const date = new Intl.DateTimeFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { dateStyle: 'long' });
  return (
    <main className="site-section">
      <h1>{t.news}</h1>
      {site.posts.length === 0 ? (
        <p>{t.noNews}</p>
      ) : (
        <ul className="site-list">
          {site.posts.map((p) => (
            <li key={p.slug}>
              <div className="meta">{date.format(new Date(p.published_at))}</div>
              <Link href={`${base}/stiri/${p.slug}`}><strong>{p.title}</strong></Link>
              {p.excerpt && <p>{p.excerpt}</p>}
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
