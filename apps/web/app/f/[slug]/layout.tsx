import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { CSSProperties, ReactNode } from 'react';
import { getSite, siteBase, siteLang, siteText } from '@/lib/site';

export default async function SiteLayout({ children, params }: { children: ReactNode; params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const site = await getSite(slug);
  if (!site) notFound();
  const t = siteText[siteLang(site)];
  const base = await siteBase(slug);

  return (
    <div className="site" lang={siteLang(site)} style={{ '--site-accent': site.accent_color } as CSSProperties}>
      <header className="site-header">
        <Link href={base || '/'} className="site-brand">
          {site.logo_url ? <img src={site.logo_url} alt="" className="site-logo" /> : null}
          <span>{site.name}</span>
        </Link>
        <nav aria-label={site.name} className="site-nav">
          <Link href={`${base}/stiri`}>{t.news}</Link>
          <a href={`${base || ''}/#contact`}>{t.contact}</a>
          <a href={`${base || ''}/#cerere`} className="site-nav-cta">{t.request}</a>
        </nav>
      </header>
      {children}
      <footer className="site-footer" id="contact">
        <div>
          <strong>{site.name}</strong>
          {site.address && <div>{site.address}</div>}
          {site.phone && <div><a href={`tel:${site.phone}`}>{site.phone}</a></div>}
          {site.email && <div><a href={`mailto:${site.email}`}>{site.email}</a></div>}
        </div>
        <div className="meta">{t.poweredBy}</div>
      </footer>
    </div>
  );
}
