'use client';
import { useState, type FormEvent } from 'react';
import type { landingCopy } from '@/lib/landing-copy';
type Copy = (typeof landingCopy)['ro'] | (typeof landingCopy)['de'];
export function LandingSearch({ copy: c }: { copy: Copy }) {
 const [scheduled, setScheduled] = useState(false);
 const [error, setError] = useState('');
 const [busy, setBusy] = useState(false);
 function submit(event: FormEvent<HTMLFormElement>) {
  event.preventDefault(); setError('');
  const data = new FormData(event.currentTarget);
  const query = new URLSearchParams({ to: String(data.get('to') ?? '').trim(), pax: String(data.get('pax') ?? '2') });
  if (scheduled) query.set('date', String(data.get('date') ?? ''));
  const from = String(data.get('from') ?? '').trim();
  if (from && from !== c.gps) { query.set('from', from); window.location.assign('/cauta?' + query); return; }
  if (!navigator.geolocation) { setError(c.gpsError); return; }
  setBusy(true);
  navigator.geolocation.getCurrentPosition(({ coords }) => {
   query.set('lat', String(coords.latitude)); query.set('lng', String(coords.longitude));
   window.location.assign('/cauta?' + query);
  }, () => { setBusy(false); setError(c.gpsError); }, { timeout: 10000, maximumAge: 60000 });
 }
 return <form id="cauta-cursa" className="landing-search" onSubmit={submit}>
  <label>{c.from}<input name="from" aria-label={c.from} defaultValue={c.gps} autoComplete="off" /></label>
  <label>{c.to}<input name="to" aria-label={c.to} placeholder={c.destination} required autoComplete="off" /></label>
  <fieldset><legend>{c.when}</legend><div className="when-tabs"><button type="button" aria-pressed={!scheduled} onClick={()=>setScheduled(false)}>{c.now}</button><button type="button" aria-pressed={scheduled} onClick={()=>setScheduled(true)}>{c.scheduled}</button></div>{scheduled && <input className="scheduled-date" type="date" name="date" aria-label={c.date} min={new Date().toLocaleDateString('sv-SE')} required />}</fieldset>
  <label>{c.persons}<input name="pax" type="number" min="1" max="20" defaultValue="2" required /></label>
  <button className="landing-button search-submit" disabled={busy}>{busy ? c.gpsLoading : c.submit}</button>
  {error && <p role="alert" className="alert alert-error landing-search-error">{error}</p>}
 </form>;
}
