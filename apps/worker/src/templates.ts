// Textele mesajelor către clienți, pe limbă. Fără date despre alți clienți.

export type Locale = 'ro' | 'de' | 'en';

export type OutboxParams = {
  trip_title?: string;
  company?: string;
  minutes?: number;
  eta_at?: string;
};

const TIME_ZONES: Record<Locale, string> = { ro: 'Europe/Bucharest', de: 'Europe/Vienna', en: 'Europe/Bucharest' };

function time(iso: string | undefined, locale: Locale): string {
  if (!iso) return '';
  return new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : locale === 'en' ? 'en-GB' : 'ro-RO', {
    timeZone: TIME_ZONES[locale],
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));
}

type Render = (p: OutboxParams, link: string | null, locale: Locale) => string;

const templates: Record<string, Record<Locale, Render>> = {
  BOOKING_CONFIRMED: {
    ro: (p, link) => `${p.company}: rezervarea ta pentru ${p.trip_title} e confirmată.${link ? ` Urmărește cursa: ${link}` : ''}`,
    de: (p, link) => `${p.company}: Deine Buchung für ${p.trip_title} ist bestätigt.${link ? ` Fahrt verfolgen: ${link}` : ''}`,
    en: (p, link) => `${p.company}: your booking for ${p.trip_title} is confirmed.${link ? ` Track your ride: ${link}` : ''}`,
  },
  PICKUP_ETA: {
    ro: (p, link, l) => `${p.company}: microbuzul ajunge la tine în aprox. ${p.minutes} minute (${time(p.eta_at, l)}).${link ? ` ${link}` : ''}`,
    de: (p, link, l) => `${p.company}: Der Kleinbus ist in ca. ${p.minutes} Minuten bei dir (${time(p.eta_at, l)}).${link ? ` ${link}` : ''}`,
    en: (p, link, l) => `${p.company}: your minibus arrives in about ${p.minutes} minutes (${time(p.eta_at, l)}).${link ? ` ${link}` : ''}`,
  },
  DRIVER_ARRIVED: {
    ro: (p, link) => `${p.company}: șoferul a ajuns la punctul de preluare.${link ? ` ${link}` : ''}`,
    de: (p, link) => `${p.company}: Der Fahrer ist am Abholort angekommen.${link ? ` ${link}` : ''}`,
    en: (p, link) => `${p.company}: your driver has arrived at the pickup point.${link ? ` ${link}` : ''}`,
  },
  TRIP_CANCELLED: {
    ro: (p) => `${p.company}: cursa ${p.trip_title} a fost anulată. Te contactăm pentru o variantă nouă.`,
    de: (p) => `${p.company}: Die Fahrt ${p.trip_title} wurde storniert. Wir melden uns mit einer Alternative.`,
    en: (p) => `${p.company}: the trip ${p.trip_title} was cancelled. We will contact you with an alternative.`,
  },
};

/** Mesajele care primesc linkul de urmărire. */
export const TEMPLATES_WITH_LINK = new Set(['BOOKING_CONFIRMED', 'PICKUP_ETA', 'DRIVER_ARRIVED']);

export function renderMessage(templateKey: string, locale: string, params: OutboxParams, link: string | null): string {
  const byLocale = templates[templateKey];
  if (!byLocale) throw new Error(`Șablon necunoscut: ${templateKey}`);
  const l: Locale = locale === 'de' || locale === 'en' ? locale : 'ro';
  return byLocale[l](params, link, l);
}
