'use client';

import { useActionState } from 'react';
import { submitRequest, type RequestState } from './actions';

type Labels = Record<
  'formTitle' | 'formHelp' | 'name' | 'phone' | 'email' | 'fromPlace' | 'toPlace' | 'date' | 'persons' | 'message'
  | 'send' | 'sending' | 'sent' | 'formError' | 'limit' | 'privacy',
  string
>;

export function RequestForm({ slug, locale, labels }: { slug: string; locale: string; labels: Labels }) {
  const [state, action, pending] = useActionState<RequestState, FormData>(submitRequest, { status: 'idle' });
  if (state.status === 'sent') return <p className="alert alert-ok" role="status">{labels.sent}</p>;
  return (
    <form action={action} className="form site-form">
      <input type="hidden" name="slug" value={slug} />
      <input type="hidden" name="locale" value={locale} />
      <div aria-hidden="true" style={{ position: 'absolute', left: '-9999px' }}>
        <label>Website<input name="website" tabIndex={-1} autoComplete="off" /></label>
      </div>
      {state.status === 'error' && <p role="alert" className="alert alert-error">{labels.formError}</p>}
      {state.status === 'limit' && <p role="alert" className="alert alert-error">{labels.limit}</p>}
      <div className="row">
        <label>{labels.name}<input name="full_name" required minLength={2} maxLength={120} autoComplete="name" /></label>
        <label>{labels.phone}<input name="phone" type="tel" required minLength={6} maxLength={40} autoComplete="tel" /></label>
      </div>
      <div className="row">
        <label>{labels.fromPlace}<input name="from" required minLength={2} maxLength={160} /></label>
        <label>{labels.toPlace}<input name="to" required minLength={2} maxLength={160} /></label>
      </div>
      <div className="row">
        <label>{labels.date}<input name="date" type="date" /></label>
        <label>{labels.persons}<input name="passengers" type="number" min={1} max={60} defaultValue={1} required /></label>
      </div>
      <label>{labels.email}<input name="email" type="email" maxLength={120} autoComplete="email" /></label>
      <label>{labels.message}<textarea name="message" maxLength={1000} /></label>
      <p className="meta" style={{ margin: 0 }}>{labels.privacy}</p>
      <button className="btn btn-primary site-btn" disabled={pending}>{pending ? labels.sending : labels.send}</button>
    </form>
  );
}
