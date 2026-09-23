'use server';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
export async function changeLandingLocale(form: FormData) {
  const locale = form.get('locale') === 'de' ? 'de' : 'ro';
  (await cookies()).set('locale', locale, { httpOnly: true, sameSite: 'lax', path: '/', maxAge: 31536000 });
  redirect('/');
}
