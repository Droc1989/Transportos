import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { FEATURE_LABELS, type VehicleFeature } from '@transportos/shared';
import { RichText, plainText } from '@/lib/rich-text';
import { getSite, languageName, siteBase, siteLang, siteText, waLink } from '@/lib/site';
import { RequestForm } from './request-form';

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const site = await getSite(slug);
  if (!site) return {};
  const description = site.seo_description ?? (plainText(site.about) || site.tagline || site.name);
  return {
    title: site.tagline ? `${site.name} – ${site.tagline}` : site.name,
    description,
    openGraph: { title: site.name, description, images: site.cover_url ? [site.cover_url] : undefined, type: 'website' },
  };
}

export default async function SiteHome({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const site = await getSite(slug);
  if (!site) notFound();
  const lang = siteLang(site);
  const t = siteText[lang];
  const base = await siteBase(slug);
  const wa = waLink(site.whatsapp);
  const date = new Intl.DateTimeFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { dateStyle: 'long' });
  const eur = new Intl.NumberFormat(lang === 'de' ? 'de-AT' : 'ro-RO', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 });

  return (
    <main>
      <section className="site-hero" style={site.cover_url ? { backgroundImage: `linear-gradient(rgba(14,26,43,.55), rgba(14,26,43,.7)), url(${site.cover_url})` } : undefined}>
        <h1>{site.name}</h1>
        {site.tagline && <p className="site-tagline">{site.tagline}</p>}
        <div className="site-cta">
          {site.phone && <a className="btn site-btn" href={`tel:${site.phone}`}>{t.call}</a>}
          {wa && <a className="btn site-btn-light" href={wa} target="_blank" rel="noreferrer">{t.whatsapp}</a>}
          <a className="btn site-btn-light" href="#cerere">{t.request}</a>
        </div>
      </section>

      {site.about && (
        <section className="site-section site-prose">
          <h2>{t.about}</h2>
          <RichText text={site.about} />
        </section>
      )}

      {site.routes.length > 0 && (
        <section className="site-section">
          <h2>{t.routes}</h2>
          <ul className="site-grid">
            {site.routes.map((r) => (
              <li key={r.name} className="site-card">
                <strong>{r.name}</strong>
                <div className="site-route">{r.points.join(' → ')}</div>
                {r.note && <div className="meta">{r.note}</div>}
                {r.price_from_cents !== null && <div className="site-price">{t.from} {eur.format(r.price_from_cents / 100)}</div>}
              </li>
            ))}
          </ul>
        </section>
      )}

      {site.fleet.length > 0 && (
        <section className="site-section">
          <h2>{t.fleet}</h2>
          <ul className="site-grid">
            {site.fleet.map((v) => (
              <li key={v.label} className="site-card">
                {v.photo_url && <img src={v.photo_url} alt={v.label} className="site-photo" loading="lazy" />}
                <strong>{v.label}</strong> <span className="meta">· {v.seats} {t.seats}{v.year ? ` · ${v.year}` : ''}</span>
                {v.description && <p>{v.description}</p>}
                {(v.features.length > 0 || v.amenities.length > 0) && (
                  <div className="site-tags">
                    {v.features.map((f) => <span key={f}>{FEATURE_LABELS[lang][f as VehicleFeature] ?? f}</span>)}
                    {v.amenities.filter((a) => !v.features.length).map((a) => <span key={a}>{a}</span>)}
                  </div>
                )}
                {v.photos.length > 1 && (
                  <div className="site-thumbs">
                    {v.photos.slice(1, 4).map((p) => <img key={p.url} src={p.url} alt="" loading="lazy" />)}
                  </div>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {site.drivers.length > 0 && (
        <section className="site-section">
          <h2>{t.drivers}</h2>
          <ul className="site-grid">
            {site.drivers.map((d) => (
              <li key={d.name} className="site-card site-driver">
                {d.photo_url ? <img src={d.photo_url} alt={d.name} className="site-avatar" loading="lazy" /> : <div className="site-avatar site-avatar-empty" aria-hidden="true">{d.name.slice(0, 1)}</div>}
                <div>
                  <strong>{d.name}</strong>
                  {d.driving_since && <div className="meta">{t.since} {d.driving_since}</div>}
                  {d.languages.length > 0 && <div className="meta">{t.languages}: {d.languages.map((l) => languageName(l, lang)).join(', ')}</div>}
                  {d.bio && <p>{d.bio}</p>}
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}

      {site.posts.length > 0 && (
        <section className="site-section">
          <h2>{t.news}</h2>
          <ul className="site-grid">
            {site.posts.slice(0, 3).map((p) => (
              <li key={p.slug} className="site-card">
                {p.cover_url && <img src={p.cover_url} alt="" className="site-photo" loading="lazy" />}
                <div className="meta">{date.format(new Date(p.published_at))}</div>
                <Link href={`${base}/stiri/${p.slug}`}><strong>{p.title}</strong></Link>
                {p.excerpt && <p>{p.excerpt}</p>}
              </li>
            ))}
          </ul>
          {site.posts.length > 3 && <p><Link href={`${base}/stiri`}>{t.allNews}</Link></p>}
        </section>
      )}

      <section className="site-section" id="cerere">
        <h2>{t.formTitle}</h2>
        <p className="meta">{t.formHelp}</p>
        <RequestForm slug={site.slug} locale={lang} labels={t} />
      </section>
    </main>
  );
}
