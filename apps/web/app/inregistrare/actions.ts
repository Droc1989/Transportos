'use server';

import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export type SignUpState = { error: boolean; checkEmail: boolean };

function safeNext(next: string) {
  return next.startsWith('/') && !next.startsWith('//') ? next : '/invitatie';
}

export async function signUp(_prev: SignUpState, form: FormData): Promise<SignUpState> {
  const email = String(form.get('email') ?? '').trim();
  const password = String(form.get('password') ?? '');
  const next = safeNext(String(form.get('next') ?? '/invitatie'));
  if (!email || password.length < 8) return { error: true, checkEmail: false };

  const origin = (await headers()).get('origin') ?? '';
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { emailRedirectTo: `${origin}/login?next=${encodeURIComponent(next)}` },
  });
  if (error) return { error: true, checkEmail: false };

  // Cu confirmarea pe email activă nu există încă sesiune.
  if (!data.session) return { error: false, checkEmail: true };
  redirect(next);
}
