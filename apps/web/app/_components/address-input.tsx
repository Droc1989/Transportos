'use client';

import { useEffect, useId, useRef, useState } from 'react';
import { LatestRequest } from '@/lib/latest-request';

type AddressOption = { label: string; lat: number; lng: number; postcode: string | null };

/**
 * Câmp de adresă (stradă și număr) cu sugestii din jurul localității alese.
 * Trimite textul în `name` și coordonatele adresei alese în `${name}_lat` / `${name}_lng`.
 * Adresa se poate scrie și liber (sate fără nume de străzi): atunci coordonatele rămân goale.
 */
export function AddressInput({
  name, near, nearLat, nearLng, placeholder, required, noResults, defaultText = '',
}: {
  name: string; near?: string; nearLat?: number; nearLng?: number; placeholder?: string; required?: boolean;
  noResults?: string; defaultText?: string;
}) {
  const [text, setText] = useState(defaultText);
  const [point, setPoint] = useState<{ lat: number; lng: number } | null>(null);
  const [options, setOptions] = useState<AddressOption[]>([]);
  const [attribution, setAttribution] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const [searched, setSearched] = useState(false);
  const listId = useId();
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const requests = useRef(new LatestRequest());

  useEffect(() => {
    const current = requests.current;
    return () => { if (timer.current) clearTimeout(timer.current); current.invalidate(); };
  }, [near, nearLat, nearLng]);

  function search(value: string) {
    if (timer.current) clearTimeout(timer.current);
    requests.current.invalidate();
    setOptions([]); setOpen(false); setActive(-1); setSearched(false);
    if (value.trim().length < 3) { setOptions([]); setOpen(false); setSearched(false); return; }
    // Așteptăm să termine de scris: fiecare căutare consumă din cota serviciului de adrese.
    timer.current = setTimeout(async () => {
      const request = requests.current.start();
      const params = new URLSearchParams({ q: value });
      if (nearLat !== undefined && nearLng !== undefined) { params.set('lat', String(nearLat)); params.set('lng', String(nearLng)); }
      else if (near) params.set('near', near);
      try {
        const res = await fetch(`/api/addresses?${params}`, { signal: request.signal });
        const data = (await res.json()) as { items: AddressOption[]; attribution: string | null; provider: string | null };
        if (!request.isCurrent() || !data.provider) return;
        setOptions(data.items); setAttribution(data.attribution); setActive(data.items.length ? 0 : -1);
        setOpen(true); setSearched(true);
      } catch { /* anulat sau fără rețea */ }
    }, 350);
  }

  function pick(o: AddressOption) {
    if (timer.current) clearTimeout(timer.current);
    requests.current.invalidate();
    setText(o.label); setPoint({ lat: o.lat, lng: o.lng }); setOpen(false); setOptions([]);
  }

  return (
    <div className="place-field">
      <input
        name={name} value={text} placeholder={placeholder} required={required} autoComplete="off"
        role="combobox" aria-expanded={open} aria-controls={listId} aria-autocomplete="list"
        aria-activedescendant={open && active >= 0 ? `${listId}-${active}` : undefined}
        onChange={(e) => { setText(e.target.value); setPoint(null); search(e.target.value); }}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
        onKeyDown={(e) => {
          if (!open || options.length === 0) return;
          if (e.key === 'ArrowDown') { e.preventDefault(); setActive((a) => (a + 1) % options.length); }
          else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((a) => (a - 1 + options.length) % options.length); }
          else if (e.key === 'Enter' && active >= 0) { e.preventDefault(); pick(options[active]!); }
          else if (e.key === 'Escape') setOpen(false);
        }}
      />
      <input type="hidden" name={`${name}_lat`} value={point?.lat ?? ''} />
      <input type="hidden" name={`${name}_lng`} value={point?.lng ?? ''} />
      {open && (
        <ul id={listId} role="listbox" className="place-suggest">
          {options.map((o, i) => (
            <li key={`${o.label}-${i}`} id={`${listId}-${i}`} role="option" aria-selected={i === active}
              onMouseDown={(e) => { e.preventDefault(); pick(o); }}>
              <span className="place-name">{o.label}</span>
            </li>
          ))}
          {searched && options.length === 0 && noResults && <li className="place-empty">{noResults}</li>}
          {attribution && <li className="place-attribution" aria-hidden="true">{attribution}</li>}
        </ul>
      )}
    </div>
  );
}
