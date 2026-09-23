'use client';

import { useActionState, useState } from 'react';
import type { FormState } from '@/lib/form';
import { PlaceInput, type PlaceOption } from '../../_components/place-input';
import { saveRoute } from './actions';


type Labels = Record<'name' | 'points' | 'pick' | 'add' | 'remove' | 'up' | 'down' | 'create' | 'saving' | 'noPlace', string>;

export function RouteBuilder({ labels }: { labels: Labels }) {
  const [state, action, pending] = useActionState<FormState, FormData>(async (prev, form) => {
    const result = await saveRoute(prev, form);
    if (!result.error) setPoints([]);
    return result;
  }, { error: null });
  const [points, setPoints] = useState<PlaceOption[]>([]);
  const [pick, setPick] = useState<PlaceOption | null>(null);
  const [pickKey, setPickKey] = useState(0);

  const move = (index: number, delta: number) =>
    setPoints((list) => {
      const next = [...list];
      const target = index + delta;
      if (target < 0 || target >= next.length) return list;
      [next[index], next[target]] = [next[target]!, next[index]!];
      return next;
    });

  return (
    <form action={action} className="form">
      {state.error && <p role="alert" className="alert alert-error">{state.error}</p>}
      <fieldset>
        <legend>{labels.create}</legend>
        <label>
          {labels.name}
          <input name="name" required maxLength={80} placeholder="Timișoara – München prin Wien" />
        </label>

        <div className="field">
          <span className="field-label">{labels.points}</span>
          <ol className="stops">
            {points.map((p, i) => (
              <li key={`${p.id}-${i}`}>
                <input type="hidden" name="place_id" value={p.id} />
                <span className="stop-no">{i + 1}</span>
                <span className="stop-name">
                  {p.name} <span className="meta">{[p.admin_name, p.country].filter(Boolean).join(' · ')}</span>
                </span>
                <button type="button" className="btn btn-small" onClick={() => move(i, -1)} aria-label={labels.up} disabled={i === 0}>↑</button>
                <button type="button" className="btn btn-small" onClick={() => move(i, 1)} aria-label={labels.down} disabled={i === points.length - 1}>↓</button>
                <button type="button" className="btn btn-small" onClick={() => setPoints((l) => l.filter((_, j) => j !== i))} aria-label={labels.remove}>✕</button>
              </li>
            ))}
          </ol>
          <div className="inline">
            {/* Orice localitate din RO, AT, DE, HU: se caută după nume, cu sugestii. */}
            <PlaceInput key={pickKey} name="pick_place" ariaLabel={labels.pick} placeholder={labels.pick}
              noResults={labels.noPlace} onPick={(p) => setPick(p)} />
            <button
              type="button"
              className="btn btn-small"
              disabled={!pick}
              onClick={() => {
                if (!pick) return;
                setPoints((l) => [...l, pick]);
                setPick(null);
                setPickKey((k) => k + 1);
              }}
            >
              {labels.add}
            </button>
          </div>
        </div>
      </fieldset>
      <button className="btn btn-primary" disabled={pending || points.length < 2}>
        {pending ? labels.saving : labels.create}
      </button>
    </form>
  );
}
