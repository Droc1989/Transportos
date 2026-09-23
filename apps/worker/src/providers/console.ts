import type { NotificationMessage, NotificationProvider } from '@transportos/shared';

/** Pentru dezvoltare: afișează mesajul în loc să-l trimită. Numărul e parțial ascuns. */
export class ConsoleNotificationProvider implements NotificationProvider {
  async send(message: NotificationMessage): Promise<{ providerMessageId: string }> {
    const masked = message.to.replace(/\d(?=\d{3})/g, '•');
    console.log(`[${message.channel} → ${masked}] ${message.params.text}`);
    return { providerMessageId: `console-${Date.now()}` };
  }
}
