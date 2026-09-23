'use client';

import { useActionState, useState } from 'react';
import type { FormState } from '@/lib/form';
import { saveRoute } from './actions';

export type Place = { id: string; name: string; country: string };

type Labels = Record<'name' | 'points' | 'pick' | 'add' | 'remove' | 'up' | 'down' | 'create' | 'saving', string>;

const COUNTRY_ORDER = ['RO', 'HU', 'AT', 'DE'];

export function RouteBuilder({ places, labels }: { places: Place[]; labels: Labels }) {
  const [state, action, pending] = useActionState<FormState, FormData>(async (prev, form) => {
    const result = await saveRoute(prev, form);
    if (!result.error) setPoints([]);
    return result;
  }, { error: null });
  const [points, setPoints] = useState<string[]>([]);
  const [pick, setPick] = useState('');
  const byId = new Map(places.map((p) => [p.id, p]));

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
            {points.map((id, i) => (
              <li key={`${id}-${i}`}>
                <input type="hidden" name="place_id" value={id} />
                <span className="stop-no">{i + 1}</span>
                <span className="stop-name">
                  {byId.get(id)?.name} <span className="meta">{byId.get(id)?.country}</span>
                </span>
                <button type="button" className="btn btn-small" onClick={() => move(i, -1)} aria-label={labels.up} disabled={i === 0}>↑</button>
                <button type="button" className="btn btn-small" onClick={() => move(i, 1)} aria-label={labels.down} disabled={i === points.length - 1}>↓</button>
                <button type="button" className="btn btn-small" onClick={() => setPoints((l) => l.filter((_, j) => j !== i))} aria-label={labels.remove}>✕</button>
              </li>
            ))}
          </ol>
          <div className="inline">
            <select value={pick} onChange={(e) => setPick(e.target.value)} aria-label={labels.pick}>
              <option value="">{labels.pick}</option>
              {COUNTRY_ORDER.map((country) => (
                <optgroup key={country} label={country}>
                  {places.filter((p) => p.country === country).map((p) => (
                    <option key={p.id} value={p.id}>{p.name}</option>
                  ))}
                </optgroup>
              ))}
            </select>
            <button
              type="button"
              className="btn btn-small"
              disabled={!pick}
              onClick={() => {
                setPoints((l) => [...l, pick]);
                setPick('');
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
