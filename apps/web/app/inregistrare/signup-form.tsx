'use client';

import { useActionState } from 'react';
import { signUp, type SignUpState } from './actions';

type Labels = Record<'email' | 'password' | 'submit' | 'error' | 'check', string>;

export function SignUpForm({ next, labels }: { next: string; labels: Labels }) {
  const [state, action, pending] = useActionState<SignUpState, FormData>(signUp, { error: false, checkEmail: false });
  if (state.checkEmail) return <p className="alert alert-ok" role="status">{labels.check}</p>;
  return (
    <form action={action} className="form">
      <input type="hidden" name="next" value={next} />
      {state.error && <p role="alert" className="alert alert-error">{labels.error}</p>}
      <label>
        {labels.email}
        <input name="email" type="email" autoComplete="email" required />
      </label>
      <label>
        {labels.password}
        <input name="password" type="password" autoComplete="new-password" minLength={8} required />
      </label>
      <button className="btn btn-primary" disabled={pending}>{labels.submit}</button>
    </form>
  );
}
