import type { NotificationMessage, NotificationProvider } from '@transportos/shared';

/** Email prin API-ul Resend (fără SDK). */
export class ResendEmailProvider implements NotificationProvider {
  constructor(private readonly apiKey: string, private readonly from: string) {}

  async send(message: NotificationMessage): Promise<{ providerMessageId: string }> {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: this.from,
        to: [message.to],
        subject: message.params.subject ?? 'TransportOS',
        text: message.params.text ?? '',
      }),
      signal: AbortSignal.timeout(15000),
    });
    const json = (await res.json()) as { id?: string; message?: string };
    if (!res.ok || !json.id) throw new Error(`Resend ${res.status}: ${json.message ?? 'eroare'}`);
    return { providerMessageId: json.id };
  }
}
