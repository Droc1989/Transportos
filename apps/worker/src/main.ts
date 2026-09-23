// Worker de sistem TransportOS (docs/api-baza-de-date.md, secțiunea „Worker de sistem”).
// Rulează continuu (`npm start`) sau o singură tură (`npm run once`, pentru cron).
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { NotificationChannel, NotificationProvider } from '@transportos/shared';
import { ConsoleNotificationProvider } from './providers/console';
import { TwilioNotificationProvider } from './providers/twilio';
import { ResendEmailProvider } from './providers/resend';
import { COMPANY_TEMPLATES, renderMessage, subjectFor, TEMPLATES_WITH_LINK, type OutboxParams } from './templates';

type OutboxRow = {
  id: number;
  booking_id: string | null;
  template_key: string;
  channel: NotificationChannel;
  recipient: string;
  locale: string;
  params: OutboxParams;
};

function env(name: string, required = true): string | undefined {
  const value = process.env[name];
  if (required && !value) throw new Error(`Lipsește variabila de mediu ${name}`);
  return value || undefined;
}

function buildProviders(): Partial<Record<NotificationChannel, NotificationProvider>> {
  // Fără furnizor configurat pentru un canal: mesajele se afișează în consolă.
  const consoleProvider = new ConsoleNotificationProvider();
  const providers: Partial<Record<NotificationChannel, NotificationProvider>> = {
    WHATSAPP: consoleProvider, SMS: consoleProvider, PUSH: consoleProvider, EMAIL: consoleProvider,
  };
  const sid = env('TWILIO_ACCOUNT_SID', false);
  const token = env('TWILIO_AUTH_TOKEN', false);
  if (sid && token) {
    const twilio = new TwilioNotificationProvider(sid, token, env('TWILIO_WHATSAPP_FROM', false) ?? '', env('TWILIO_SMS_FROM', false));
    providers.WHATSAPP = twilio;
    providers.SMS = twilio;
  }
  const resendKey = env('RESEND_API_KEY', false);
  const emailFrom = env('EMAIL_FROM', false);
  if (resendKey && emailFrom) providers.EMAIL = new ResendEmailProvider(resendKey, emailFrom);
  return providers;
}

async function rpc<T>(db: SupabaseClient, fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}

export async function sendPending(
  db: SupabaseClient,
  providers: Partial<Record<NotificationChannel, NotificationProvider>>,
  siteUrl: string,
  limit = 50,
): Promise<{ sent: number; failed: number }> {
  const rows = await rpc<OutboxRow[]>(db, 'claim_notifications', { p_limit: limit });
  let sent = 0;
  let failed = 0;
  for (const row of rows) {
    try {
      const provider = providers[row.channel];
      if (!provider) throw new Error(`NO_PROVIDER_${row.channel}`);
      let link: string | null = null;
      if (COMPANY_TEMPLATES[row.template_key]) {
        link = `${siteUrl.replace(/\/$/, '')}${COMPANY_TEMPLATES[row.template_key]}`;
      } else if (row.booking_id && TEMPLATES_WITH_LINK.has(row.template_key)) {
        const token = await rpc<string | null>(db, 'worker_tracking_link', { p_booking_id: row.booking_id });
        link = token ? `${siteUrl.replace(/\/$/, '')}/u/${token}` : null;
      }
      const text = renderMessage(row.template_key, row.locale, row.params, link);
      await provider.send({
        to: row.recipient,
        channel: row.channel,
        templateKey: row.template_key,
        params: { text, subject: subjectFor(row.template_key, row.locale) },
        locale: row.locale === 'de' || row.locale === 'en' ? row.locale : 'ro',
      });
      await rpc(db, 'finish_notification', { p_id: row.id, p_ok: true });
      sent += 1;
    } catch (error) {
      await rpc(db, 'finish_notification', { p_id: row.id, p_ok: false, p_error: (error as Error).message });
      failed += 1;
    }
  }
  return { sent, failed };
}

export async function runCycle(db: SupabaseClient, providers: Partial<Record<NotificationChannel, NotificationProvider>>, siteUrl: string) {
  const eta = await rpc<number>(db, 'enqueue_eta_notifications');
  const map = await rpc<number>(db, 'refresh_public_live_trips');
  const result = await sendPending(db, providers, siteUrl);
  return { eta, map, ...result };
}

async function main() {
  const db = createClient(env('SUPABASE_URL')!, env('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const providers = buildProviders();
  const siteUrl = env('SITE_URL')!;
  const once = process.argv.includes('--once');

  let lastRetention = 0;
  do {
    const started = Date.now();
    try {
      const r = await runCycle(db, providers, siteUrl);
      if (r.eta || r.sent || r.failed) {
        console.log(`[tură] ETA noi: ${r.eta}, trimise: ${r.sent}, eșuate: ${r.failed}, harta publică: ${r.map} curse`);
      }
      if (Date.now() - lastRetention > 24 * 3600 * 1000) {
        const res = await rpc<Record<string, number>>(db, 'run_retention');
        console.log('[retenție]', JSON.stringify(res));
        lastRetention = Date.now();
      }
    } catch (error) {
      console.error('[eroare tură]', (error as Error).message);
      if (once) process.exitCode = 1;
    }
    if (!once) await new Promise((r) => setTimeout(r, Math.max(0, 30_000 - (Date.now() - started))));
  } while (!once);
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('main.ts')) {
  void main();
}
