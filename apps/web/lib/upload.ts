import type { SupabaseClient } from '@supabase/supabase-js';

const ALLOWED: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
const MAX_BYTES = 5 * 1024 * 1024;

/**
 * Încarcă o poză în bucketul public „site-media”, în folderul firmei (regulile din Storage
 * permit fiecărei firme să scrie doar la ea). Întoarce adresa publică sau null dacă nu e fișier.
 */
export async function uploadSiteImage(
  supabase: SupabaseClient,
  companyId: string,
  file: FormDataEntryValue | null,
  folder: 'logo' | 'cover' | 'fleet' | 'drivers' | 'posts',
  subfolder?: string,
): Promise<string | null> {
  if (!(file instanceof File) || file.size === 0) return null;
  const ext = ALLOWED[file.type];
  if (!ext) throw new Error('IMAGE_TYPE');
  if (file.size > MAX_BYTES) throw new Error('IMAGE_TOO_LARGE');
  const path = `${companyId}/${folder}/${subfolder ? `${subfolder}/` : ''}${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from('site-media').upload(path, file, { contentType: file.type, upsert: false });
  if (error) throw error;
  return supabase.storage.from('site-media').getPublicUrl(path).data.publicUrl;
}
