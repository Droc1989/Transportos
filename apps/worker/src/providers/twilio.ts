import type { NotificationMessage, NotificationProvider } from '@transportos/shared';

/** WhatsApp și SMS prin API-ul Twilio (fără SDK). */
export class TwilioNotificationProvider implements NotificationProvider {
  constructor(
    private readonly accountSid: string,
    private readonly authToken: string,
    private readonly whatsappFrom: string,
    private readonly smsFrom: string | undefined,
  ) {}

  async send(message: NotificationMessage): Promise<{ providerMessageId: string }> {
    const whatsapp = message.channel === 'WHATSAPP';
    if (!whatsapp && !this.smsFrom) throw new Error('TWILIO_SMS_FROM nu e setat');
    const body = new URLSearchParams({
      From: whatsapp ? this.whatsappFrom : this.smsFrom!,
      To: whatsapp ? `whatsapp:${message.to}` : message.to,
      Body: message.params.text ?? '',
    });
    const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Messages.json`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64')}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
      signal: AbortSignal.timeout(15000),
    });
    const json = (await res.json()) as { sid?: string; message?: string };
    if (!res.ok || !json.sid) throw new Error(`Twilio ${res.status}: ${json.message ?? 'eroare'}`);
    return { providerMessageId: json.sid };
  }
}
