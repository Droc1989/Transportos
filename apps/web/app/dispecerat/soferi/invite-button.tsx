'use client';

import { useActionState, useState } from 'react';
import { createInvite, type InviteState } from './actions';

type Labels = Record<'button' | 'title' | 'help' | 'copy' | 'copied' | 'whatsapp' | 'message', string>;

/** Generează codul de invitație și îl arată o singură dată, cu copiere și WhatsApp. */
export function InviteButton({ driverId, phone, labels }: { driverId: string; phone: string | null; labels: Labels }) {
  const [state, action, pending] = useActionState<InviteState, FormData>(createInvite, { code: null, error: null });
  const [copied, setCopied] = useState(false);

  if (state.code) {
    const message = `${labels.message} ${state.code}`;
    const waNumber = phone?.replace(/[^\d]/g, '') ?? '';
    const waUrl = `https://wa.me/${waNumber}?text=${encodeURIComponent(message)}`;
    return (
      <div className="invite" role="status">
        <div className="meta">{labels.title}</div>
        <div className="invite-code">{state.code}</div>
        <p className="meta" style={{ margin: 0 }}>{labels.help}</p>
        <div className="actions" style={{ justifyContent: 'flex-start' }}>
          <button
            type="button"
            className="btn btn-small"
            onClick={async () => {
              await navigator.clipboard.writeText(state.code ?? '');
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
    <form action={action}>
      <input type="hidden" name="id" value={driverId} />
      {state.error && <p role="alert" className="alert alert-error">{state.error}</p>}
      <button className="btn btn-small" disabled={pending}>{labels.button}</button>
    </form>
  );
}
