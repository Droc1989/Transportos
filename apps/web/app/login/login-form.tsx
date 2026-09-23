'use client';

import { useActionState } from 'react';
import { signIn } from './actions';

type Labels = { email: string; password: string; submit: string; error: string };

export function LoginForm({ next, labels }: { next: string; labels: Labels }) {
  const [state, action, pending] = useActionState(signIn, { error: false });
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
        <input name="password" type="password" autoComplete="current-password" required />
      </label>
      <button className="btn btn-primary" disabled={pending}>
        {labels.submit}
      </button>
    </form>
  );
}
