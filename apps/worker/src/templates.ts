// Textele mesajelor către clienți, pe limbă. Fără date despre alți clienți.

export type Locale = 'ro' | 'de' | 'en';

export type OutboxParams = {
  trip_title?: string;
  company?: string;
  minutes?: number;
  eta_at?: string;
  reason?: string;
  vehicle?: string;
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
  VEHICLE_CHANGED: {
    ro: (p, link) => `${p.company}: cursa ${p.trip_title} se face cu alt microbuz (${p.vehicle}). Vezi pozele și condițiile: ${link ?? ''}`.trim(),
    de: (p, link) => `${p.company}: Die Fahrt ${p.trip_title} erfolgt mit einem anderen Kleinbus (${p.vehicle}). Fotos und Ausstattung: ${link ?? ''}`.trim(),
    en: (p, link) => `${p.company}: your trip ${p.trip_title} now uses another minibus (${p.vehicle}). Photos and amenities: ${link ?? ''}`.trim(),
  },
  COMPANY_APPROVED: {
    ro: (p, link) => `Bună ziua! Firma ${p.company} a fost aprobată în TransportOS. Vă puteți autentifica cu emailul și parola alese la înscriere: ${link ?? ''}`.trim(),
    de: (p, link) => `Guten Tag! Die Firma ${p.company} wurde in TransportOS freigegeben. Melden Sie sich mit der bei der Anmeldung gewählten E-Mail und dem Passwort an: ${link ?? ''}`.trim(),
    en: (p, link) => `Hello! ${p.company} has been approved on TransportOS. Sign in with the email and password you chose: ${link ?? ''}`.trim(),
  },
  COMPANY_REJECTED: {
    ro: (p, link) => `Bună ziua! Cererea firmei ${p.company} nu a fost aprobată. Motivul: ${p.reason}. Puteți corecta datele și trimite din nou cererea: ${link ?? ''}`.trim(),
    de: (p, link) => `Guten Tag! Die Anmeldung der Firma ${p.company} wurde nicht freigegeben. Grund: ${p.reason}. Sie können die Angaben korrigieren und erneut senden: ${link ?? ''}`.trim(),
    en: (p, link) => `Hello! The application for ${p.company} was not approved. Reason: ${p.reason}. You can correct the details and resubmit: ${link ?? ''}`.trim(),
  },
  TRIP_CANCELLED: {
    ro: (p) => `${p.company}: cursa ${p.trip_title} a fost anulată. Te contactăm pentru o variantă nouă.`,
    de: (p) => `${p.company}: Die Fahrt ${p.trip_title} wurde storniert. Wir melden uns mit einer Alternative.`,
    en: (p) => `${p.company}: the trip ${p.trip_title} was cancelled. We will contact you with an alternative.`,
  },
};

/** Mesajele care primesc linkul de urmărire. */
export const TEMPLATES_WITH_LINK = new Set(['BOOKING_CONFIRMED', 'PICKUP_ETA', 'DRIVER_ARRIVED', 'VEHICLE_CHANGED']);

/** Mesajele către firmă, cu linkul de autentificare. */
export const COMPANY_TEMPLATES: Record<string, string> = {
  COMPANY_APPROVED: '/login?next=/dispecerat',
  COMPANY_REJECTED: '/login?next=/dispecerat/inscriere',
};

const SUBJECTS: Record<string, Record<Locale, string>> = {
  COMPANY_APPROVED: { ro: 'Firma a fost aprobată în TransportOS', de: 'Ihre Firma wurde in TransportOS freigegeben', en: 'Your company was approved on TransportOS' },
  COMPANY_REJECTED: { ro: 'Cererea firmei în TransportOS', de: 'Ihre Anmeldung bei TransportOS', en: 'Your TransportOS application' },
};

export function subjectFor(templateKey: string, locale: string): string {
  const l: Locale = locale === 'de' || locale === 'en' ? locale : 'ro';
  return SUBJECTS[templateKey]?.[l] ?? 'TransportOS';
}

export function renderMessage(templateKey: string, locale: string, params: OutboxParams, link: string | null): string {
  const byLocale = templates[templateKey];
  if (!byLocale) throw new Error(`Șablon necunoscut: ${templateKey}`);
  const l: Locale = locale === 'de' || locale === 'en' ? locale : 'ro';
  return byLocale[l](params, link, l);
}
