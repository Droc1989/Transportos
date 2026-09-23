import { toDomainError } from '@transportos/shared';
import { getT } from '@/lib/i18n';

export type FormState = { error: string | null };

export function text(form: FormData, name: string): string {
  return String(form.get(name) ?? '').trim();
}

/** Mesaj tradus pentru o eroare Supabase (cod de domeniu, sau generic). */
export async function errorMessage(error: { message?: string; code?: string } | null): Promise<string> {
  const { tError, locale } = await getT();
  if (error?.code === '23505') {
    return locale === 'de' ? 'Dieser Eintrag existiert bereits.' : 'Există deja o înregistrare cu aceste date.';
  }
  return tError(toDomainError(error?.message));
}
