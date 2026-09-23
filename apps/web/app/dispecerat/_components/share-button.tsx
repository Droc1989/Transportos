'use client';

import { useActionState, useState } from 'react';

export type ShareState = { value: string | null; error: string | null };

type Labels = Record<'button' | 'title' | 'help' | 'copy' | 'copied' | 'whatsapp' | 'message', string>;

/**
 * Buton care cere serverului o valoare de trimis (cod de invitație, link de urmărire)
 * și o arată o singură dată, cu copiere și trimitere pe WhatsApp.
 */
export function ShareButton({
  action,
  fields,
  phone,
  labels,
  mono = false,
}: {
  action: (prev: ShareState, form: FormData) => Promise<ShareState>;
  fields: Record<string, string>;
  phone?: string | null;
  labels: Labels;
  mono?: boolean;
}) {
  const [state, formAction, pending] = useActionState(action, { value: null, error: null });
  const [copied, setCopied] = useState(false);

  if (state.value) {
    const waNumber = phone?.replace(/[^\d]/g, '') ?? '';
    const waUrl = `https://wa.me/${waNumber}?text=${encodeURIComponent(`${labels.message} ${state.value}`)}`;
    return (
      <div className="invite" role="status">
        <div className="meta">{labels.title}</div>
        <div className={mono ? 'invite-code' : 'share-url'}>{state.value}</div>
        <p className="meta" style={{ margin: 0 }}>{labels.help}</p>
        <div className="actions" style={{ justifyContent: 'flex-start' }}>
          <button
            type="button"
            className="btn btn-small"
            onClick={async () => {
              await navigator.clipboard.writeText(state.value ?? '');
              setCopied(true);
            }}
          >
            {copied ? labels.copied : labels.copy}
          </button>
          <a className="btn btn-small btn-link" href={waUrl} target="_blank" rel="noreferrer">
            {labels.whatsapp}
          </a>
        </div>
      </div>
    );
  }

  return (
    <form action={formAction}>
      {Object.entries(fields).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      {state.error && <p role="alert" className="alert alert-error">{state.error}</p>}
      <button className="btn btn-small" disabled={pending}>{labels.button}</button>
    </form>
  );
}
