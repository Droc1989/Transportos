'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requireStaffCompany } from '@/lib/company';
import { errorMessage, text, type FormState } from '@/lib/form';
import { getT } from '@/lib/i18n';
import { uploadSiteImage } from '@/lib/upload';

async function imageOr(error: unknown): Promise<string> {
  const { t } = await getT();
  const msg = (error as Error)?.message ?? '';
  return msg.startsWith('IMAGE_') ? t('site.imageError') : errorMessage(error as { message?: string });
}

function done(companySlug?: string): never {
  revalidatePath('/dispecerat/site');
  if (companySlug) revalidatePath(`/f/${companySlug}`);
  redirect('/dispecerat/site?saved=1');
}

export async function saveSite(_prev: FormState, form: FormData): Promise<FormState> {
  const { supabase, companyId } = await requireStaffCompany();
  let logo: string | null;
  let cover: string | null;
  try {
    logo = await uploadSiteImage(supabase, companyId, form.get('logo'), 'logo');
    cover = await uploadSiteImage(supabase, companyId, form.get('cover'), 'cover');
  } catch (e) {
    return { error: await imageOr(e) };
  }
  const domain = text(form, 'custom_domain').toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').replace(/\/.*$/, '');
  const row: Record<string, unknown> = {
    company_id: companyId,
    published: form.get('published') === 'on',
    tagline: text(form, 'tagline') || null,
    about: text(form, 'about') || null,
    phone: text(form, 'phone') || null,
    whatsapp: text(form, 'whatsapp') || null,
    email: text(form, 'email') || null,
    address: text(form, 'address') || null,
    accent_color: text(form, 'accent_color') || '#0B4EA2',
    seo_description: text(form, 'seo_description') || null,
    custom_domain: domain || null,
  };
  if (logo) row.logo_url = logo;
  if (cover) row.cover_url = cover;
  const { error } = await supabase.from('company_sites').upsert(row, { onConflict: 'company_id' });
  if (error) return { error: await errorMessage(error) };
  const { data } = await supabase.from('companies').select('slug').eq('id', companyId).single<{ slug: string }>();
  done(data?.slug);
}

export async function saveRouteSite(form: FormData): Promise<void> {
  const { supabase } = await requireStaffCompany();
  const price = text(form, 'price_from');
  const { error } = await supabase
    .from('route_templates')
    .update({
      show_on_site: form.get('show_on_site') === 'on',
      public_note: text(form, 'public_note') || null,
      price_from_cents: price ? Math.round(Number(price.replace(',', '.')) * 100) : null,
    })
    .eq('id', text(form, 'id'));
  if (error) redirect(`/dispecerat/site?error=${encodeURIComponent(await errorMessage(error))}`);
  done();
}

export async function saveVehicleSite(form: FormData): Promise<void> {
  const { supabase, companyId } = await requireStaffCompany();
  let photo: string | null = null;
  try {
    photo = await uploadSiteImage(supabase, companyId, form.get('photo'), 'fleet');
  } catch (e) {
    redirect(`/dispecerat/site?error=${encodeURIComponent(await imageOr(e))}`);
  }
  const changes: Record<string, unknown> = {
    show_on_site: form.get('show_on_site') === 'on',
    public_description: text(form, 'public_description') || null,
    amenities: text(form, 'amenities').split(',').map((a) => a.trim()).filter(Boolean).slice(0, 12),
  };
  if (photo) changes.photo_url = photo;
  const { error } = await supabase.from('vehicles').update(changes).eq('id', text(form, 'id'));
  if (error) redirect(`/dispecerat/site?error=${encodeURIComponent(await errorMessage(error))}`);
  done();
}

export async function saveDriverSite(form: FormData): Promise<void> {
  const { supabase, companyId } = await requireStaffCompany();
  let photo: string | null = null;
  try {
    photo = await uploadSiteImage(supabase, companyId, form.get('photo'), 'drivers');
  } catch (e) {
    redirect(`/dispecerat/site?error=${encodeURIComponent(await imageOr(e))}`);
  }
  const since = Number(text(form, 'driving_since'));
  const { error } = await supabase.rpc('set_driver_public_profile', {
    p_driver_id: text(form, 'id'),
    p_public: form.get('public_profile') === 'on',
    p_consent: form.get('consent') === 'on',
    p_bio: text(form, 'bio') || null,
    p_languages: form.getAll('languages').map(String),
    p_driving_since: Number.isInteger(since) && since > 1950 ? since : null,
    p_photo_url: photo,
  });
  if (error) redirect(`/dispecerat/site?error=${encodeURIComponent(await errorMessage(error))}`);
  done();
}
