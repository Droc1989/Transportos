'use client';

import { useActionState, useState } from 'react';
import type { FormState } from '@/lib/form';
import { slugify } from '@/lib/slug';
import { registerCompany } from './actions';

type Labels = Record<'name' | 'slug' | 'country' | 'registrationNo' | 'licenseNo' | 'phone' | 'terms' | 'submit' | 'saving', string>;

export function CompanyForm({ labels, rootHint }: { labels: Labels; rootHint: string }) {
  const [state, action, pending] = useActionState<FormState, FormData>(registerCompany, { error: null });
  const [slug, setSlug] = useState('');
  const [touched, setTouched] = useState(false);
  return (
    <form action={action} className="form">
      {state.error && <p role="alert" className="alert alert-error">{state.error}</p>}
      <fieldset>
        <label>
          {labels.name}
          <input name="name" required minLength={2} maxLength={120} autoComplete="organization"
            onChange={(e) => { if (!touched) setSlug(slugify(e.target.value).slice(0, 60)); }} />
        </label>
        <label>
          {labels.slug}
          <input name="slug" required pattern="[a-z0-9-]{2,60}" value={slug}
            onChange={(e) => { setTouched(true); setSlug(e.target.value.toLowerCase()); }} />
          <span className="meta" style={{ fontWeight: 400 }}>{rootHint}/f/{slug || '…'}</span>
        </label>
        <div className="row">
          <label>
            {labels.country}
            <select name="country" defaultValue="RO">
              <option value="RO">România</option>
              <option value="AT">Österreich</option>
              <option value="DE">Deutschland</option>
            </select>
          </label>
          <label>{labels.phone}<input name="contact_phone" type="tel" required minLength={6} maxLength={40} autoComplete="tel" /></label>
        </div>
        <div className="row">
          <label>{labels.registrationNo}<input name="registration_no" required minLength={2} maxLength={40} /></label>
          <label>{labels.licenseNo}<input name="license_no" required minLength={2} maxLength={60} /></label>
        </div>
        <label className="check"><input type="checkbox" name="terms" required />{labels.terms}</label>
      </fieldset>
      <button className="btn btn-primary" disabled={pending}>{pending ? labels.saving : labels.submit}</button>
    </form>
  );
}
