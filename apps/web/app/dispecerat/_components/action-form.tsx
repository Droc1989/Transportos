'use client';

import { useActionState, type ReactNode } from 'react';
import type { FormState } from '@/lib/form';

/** Formular legat de un Server Action care întoarce { error }. */
export function ActionForm({
  action,
  submitLabel,
  pendingLabel,
  children,
  className = 'form',
}: {
  action: (prev: FormState, form: FormData) => Promise<FormState>;
  submitLabel: string;
  pendingLabel: string;
  children: ReactNode;
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, { error: null });
  return (
    <form action={formAction} className={className}>
      {state.error && (
        <p role="alert" className="alert alert-error">
          {state.error}
        </p>
      )}
      {children}
      <button className="btn btn-primary" disabled={pending}>
        {pending ? pendingLabel : submitLabel}
      </button>
    </form>
  );
}
