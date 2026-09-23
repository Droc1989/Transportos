'use client';

import { useEffect, useId, useRef, useState } from 'react';
import { placeLabel } from '@/lib/place-label';

export type PlaceOption = { id: string; name: string; admin_name: string | null; country: string };

/**
 * Câmp de localitate cu sugestii: vizitatorul scrie, apar localitățile potrivite (cu județul sau
 * regiunea), alege una. Trimite textul în `name` și identificatorul ales în `${name}_id`.
 * `keepText` (de ex. „Locația mea (GPS)”) nu declanșează căutarea.
 */
export function PlaceInput({
  name, defaultText = '', defaultId = '', placeholder, required, keepText, ariaLabel, noResults, inputClassName, onPick,
}: {
  name: string; defaultText?: string; defaultId?: string; placeholder?: string; required?: boolean; keepText?: string;
  ariaLabel?: string; noResults?: string; inputClassName?: string; onPick?: (p: PlaceOption) => void;
}) {
  const [text, setText] = useState(defaultText);
  const [id, setId] = useState(defaultId);
  const [options, setOptions] = useState<PlaceOption[]>([]);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const [searched, setSearched] = useState(false);
  const listId = useId();
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const abort = useRef<AbortController | null>(null);

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); abort.current?.abort(); }, []);

  function search(value: string) {
    if (timer.current) clearTimeout(timer.current);
    if (value.trim().length < 2 || value === keepText) { setOptions([]); setOpen(false); setSearched(false); return; }
    timer.current = setTimeout(async () => {
      abort.current?.abort();
      const ctrl = new AbortController();
      abort.current = ctrl;
      try {
        const res = await fetch(`/api/places?q=${encodeURIComponent(value)}`, { signal: ctrl.signal });
        const data = (await res.json()) as PlaceOption[];
        setOptions(data); setActive(data.length ? 0 : -1); setOpen(true); setSearched(true);
      } catch { /* căutare anulată sau fără rețea: nu arătăm nimic */ }
    }, 200);
  }

  function pick(p: PlaceOption) {
    setText(placeLabel(p)); setId(p.id); setOpen(false); setOptions([]);
    onPick?.(p);
  }

  return (
    <div className="place-field">
      <input
        name={name}
        value={text}
        className={inputClassName}
        placeholder={placeholder}
        required={required}
        aria-label={ariaLabel}
        autoComplete="off"
        role="combobox"
        aria-expanded={open}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={open && active >= 0 ? `${listId}-${active}` : undefined}
        onFocus={(e) => { if (text === keepText) e.currentTarget.select(); }}
        onChange={(e) => { setText(e.target.value); setId(''); search(e.target.value); }}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
        onKeyDown={(e) => {
          if (!open || options.length === 0) return;
          if (e.key === 'ArrowDown') { e.preventDefault(); setActive((a) => (a + 1) % options.length); }
          else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((a) => (a - 1 + options.length) % options.length); }
          else if (e.key === 'Enter' && active >= 0) { e.preventDefault(); pick(options[active]!); }
          else if (e.key === 'Escape') setOpen(false);
        }}
      />
      <input type="hidden" name={`${name}_id`} value={id} />
      {open && (
        <ul id={listId} role="listbox" className="place-suggest">
          {options.map((p, i) => (
            <li
              key={p.id}
              id={`${listId}-${i}`}
              role="option"
              aria-selected={i === active}
              onMouseDown={(e) => { e.preventDefault(); pick(p); }}
            >
              <span className="place-name">{p.name}</span>
              <span className="place-meta">{[p.admin_name, p.country].filter(Boolean).join(' · ')}</span>
            </li>
          ))}
          {searched && options.length === 0 && noResults && <li className="place-empty">{noResults}</li>}
        </ul>
      )}
    </div>
  );
}
