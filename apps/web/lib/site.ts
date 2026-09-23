import { headers } from 'next/headers';
import { cache } from 'react';
import { createAnonClient } from '@/lib/supabase/anon';

export type SiteData = {
  slug: string;
  name: string;
  country: string;
  locale: 'ro' | 'de' | 'en';
  tagline: string | null;
  about: string | null;
  phone: string | null;
  whatsapp: string | null;
  email: string | null;
  address: string | null;
  logo_url: string | null;
  cover_url: string | null;
  accent_color: string;
  seo_description: string | null;
  routes: { name: string; note: string | null; price_from_cents: number | null; points: string[] }[];
  fleet: { label: string; seats: number; description: string | null; photo_url: string | null; amenities: string[] }[];
  drivers: { name: string; bio: string | null; photo_url: string | null; languages: string[]; driving_since: number | null }[];
  posts: { slug: string; title: string; excerpt: string | null; cover_url: string | null; published_at: string }[];
};

export type SitePost = {
  slug: string;
  title: string;
  excerpt: string | null;
  body: string;
  cover_url: string | null;
  published_at: string;
};

/** O singură cerere pe randare, chiar dacă layout-ul și pagina cer același site. */
export const getSite = cache(async (slug: string): Promise<SiteData | null> => {
  const { data, error } = await createAnonClient().rpc('get_company_site', { p_slug: slug });
  if (error) throw error;
  return (data as SiteData | null) ?? null;
});

export const getSitePost = cache(async (slug: string, post: string): Promise<SitePost | null> => {
  const { data, error } = await createAnonClient().rpc('get_site_post', { p_slug: slug, p_post_slug: post });
  if (error) throw error;
  return (data as SitePost | null) ?? null;
});

/**
 * Prefixul linkurilor interne: „/f/<slug>” pe adresa platformei, „” pe subdomeniu sau
 * domeniul propriu (middleware-ul setează x-site-base la rescriere).
 */
export async function siteBase(slug: string): Promise<string> {
  const base = (await headers()).get('x-site-base');
  return base === null ? `/f/${slug}` : base;
}

export const siteText = {
  ro: {
    home: 'Acasă', news: 'Știri', contact: 'Contact', call: 'Sună', whatsapp: 'WhatsApp', request: 'Cere o rezervare',
    about: 'Despre noi', routes: 'Rute', from: 'de la', fleet: 'Flota', seats: 'locuri', drivers: 'Șoferii noștri',
    since: 'Conduce din', languages: 'Vorbește', allNews: 'Toate știrile', readMore: 'Citește', back: 'Înapoi la știri',
    formTitle: 'Cere o rezervare', formHelp: 'Completează și te sunăm noi pentru confirmare.',
    name: 'Nume', phone: 'Telefon', email: 'Email (opțional)', fromPlace: 'De unde pleci', toPlace: 'Unde mergi',
    date: 'Data', persons: 'Persoane', message: 'Mesaj (opțional)', send: 'Trimite cererea', sending: 'Se trimite…',
    sent: 'Mulțumim! Am primit cererea și te contactăm în curând.',
    formError: 'Verifică numele, telefonul și localitățile.', limit: 'Ai trimis deja mai multe cereri. Te rugăm să ne suni.',
    poweredBy: 'Rezervări și dispecerat cu TransportOS', noNews: 'Încă nu sunt știri.',
    privacy: 'Folosim datele doar ca să te contactăm pentru această rezervare.',
  },
  de: {
    home: 'Start', news: 'Neuigkeiten', contact: 'Kontakt', call: 'Anrufen', whatsapp: 'WhatsApp', request: 'Anfrage senden',
    about: 'Über uns', routes: 'Strecken', from: 'ab', fleet: 'Flotte', seats: 'Plätze', drivers: 'Unsere Fahrer',
    since: 'Fährt seit', languages: 'Spricht', allNews: 'Alle Neuigkeiten', readMore: 'Weiterlesen', back: 'Zurück zu den Neuigkeiten',
    formTitle: 'Buchungsanfrage', formHelp: 'Ausfüllen, wir rufen dich zur Bestätigung zurück.',
    name: 'Name', phone: 'Telefon', email: 'E-Mail (optional)', fromPlace: 'Abfahrt', toPlace: 'Ziel',
    date: 'Datum', persons: 'Personen', message: 'Nachricht (optional)', send: 'Anfrage senden', sending: 'Wird gesendet…',
    sent: 'Danke! Wir haben deine Anfrage erhalten und melden uns bald.',
    formError: 'Bitte Name, Telefon und Orte prüfen.', limit: 'Du hast bereits mehrere Anfragen gesendet. Bitte ruf uns an.',
    poweredBy: 'Buchung und Disposition mit TransportOS', noNews: 'Noch keine Neuigkeiten.',
    privacy: 'Wir nutzen die Daten nur, um dich zu dieser Buchung zu kontaktieren.',
  },
} as const;

export function siteLang(site: SiteData): 'ro' | 'de' {
  return site.locale === 'de' ? 'de' : 'ro';
}

const LANGUAGE_NAMES: Record<'ro' | 'de', Record<string, string>> = {
  ro: { ro: 'română', de: 'germană', en: 'engleză', hu: 'maghiară', ru: 'rusă', it: 'italiană', uk: 'ucraineană' },
  de: { ro: 'Rumänisch', de: 'Deutsch', en: 'Englisch', hu: 'Ungarisch', ru: 'Russisch', it: 'Italienisch', uk: 'Ukrainisch' },
};
export function languageName(code: string, lang: 'ro' | 'de'): string {
  return LANGUAGE_NAMES[lang][code] ?? code;
}

export function waLink(number: string | null): string | null {
  const digits = number?.replace(/[^\d]/g, '');
  return digits ? `https://wa.me/${digits}` : null;
}
