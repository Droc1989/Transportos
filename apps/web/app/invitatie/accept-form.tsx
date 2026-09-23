'use client';

import { useActionState } from 'react';
import { acceptInvite, type AcceptState } from './actions';

type Labels = Record<'code' | 'submit' | 'done' | 'next' | 'doneStaff' | 'openDispatch', string>;

export function AcceptForm({ labels }: { labels: Labels }) {
  const [state, action, pending] = useActionState<AcceptState, FormData>(acceptInvite, { company: null, role: null, error: null });
  if (state.company && state.role !== 'DRIVER') {
    return (
      <div className="alert alert-ok" role="status">
        {labels.doneStaff} <strong>{state.company}</strong>.{' '}
        <a href="/dispecerat">{labels.openDispatch}</a>
      </div>
    );
  }
  if (state.company) {
    return (
      <div className="alert alert-ok" role="status">
        {labels.done} <strong>{state.company}</strong>. {labels.next}
      </div>
    );
  }
  return (
    <form action={action} className="form">
      {state.error && <p role="alert" className="alert alert-error">{state.error}</p>}
      <label>
        {labels.code}
        <input
          name="code"
          required
          autoComplete="one-time-code"
          autoCapitalize="characters"
          placeholder="XXXX-XXXX"
          maxLength={12}
          className="code-input"
        />
      </label>
      <button className="btn btn-primary" disabled={pending}>{labels.submit}</button>
    </form>
  );
}
