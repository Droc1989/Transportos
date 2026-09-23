'use client';
import Link from 'next/link';
import { useActionState, useRef, useState } from 'react';
import { slugify } from '@/lib/slug';
import type { RegistrationCopy, VehiclePackage, SavedRegistration } from '@/lib/registration-copy';
import { registerCompany, sendCompanyReview } from './actions';
import './registration.css';

export function CompanyForm({copy:c,packages,saved,rootHint}:{copy:RegistrationCopy;packages:VehiclePackage[];saved:SavedRegistration|null;rootHint:string}) {
 const [step,setStep]=useState(saved?3:1);
 const [name,setName]=useState(saved?.name??''); const [slug,setSlug]=useState(saved?.slug??''); const [touched,setTouched]=useState(false);
 const [country,setCountry]=useState(saved?.country??'RO'); const [count,setCount]=useState(saved?.package.declared_vehicles??1);
 const [state,action,pending]=useActionState(registerCompany,{error:null as string|null});
 const [sent,sendAction,sending]=useActionState(sendCompanyReview,{error:null as string|null});
 const form=useRef<HTMLFormElement>(null);
 const max=Math.max(...packages.map(p=>p.vehicles_to));
 const selected=saved?{vehicles_from:saved.package.vehicles_from,vehicles_to:saved.package.vehicle_limit,monthly_eur:saved.package.monthly_eur}:packages.find(p=>count>=p.vehicles_from&&count<=p.vehicles_to);
 const displayPackages=saved&&selected?[selected]:packages;
 const vehicles=saved?.vehicles??[]; const completed=vehicles.filter(v=>v.complete).length;
 const ready=!!saved && vehicles.length>=count && vehicles.every(v=>v.complete);
 const waiting=!!saved?.submitted_at && !saved?.rejection_reason;
 const titles=[c.title,c.fleetTitle,c.profileTitle]; const intros=[c.intro,c.fleetIntro,c.profileIntro];
 function go(next:number) {if(next>step){const fields=form.current?.querySelectorAll<HTMLInputElement|HTMLSelectElement>(`[data-step="${step}"] input,[data-step="${step}"] select`);if(fields)for(const f of fields){if(!f.reportValidity())return;}}setStep(next);}
 const missing=Array.from({length:Math.max(0,count-vehicles.length)},(_,i)=>vehicles.length+i+1);
 return <main className="registration">
  <header className="reg-header"><strong>TransportOS</strong><span className="reg-desktop">{c.heading}</span><b className="reg-mobile">{c.heading.toUpperCase()} / {c.step} {step} {c.of} 3</b></header>
  <div className="reg-layout"><aside className="card reg-sidebar"><h2>{c.sidebarTitle}</h2><nav aria-label={c.heading}>{c.steps.map((s,i)=><button key={s} type="button" aria-current={step===i+1?'step':undefined} onClick={()=>{if(i+1<step)go(i+1)}} disabled={i+1>step}>{i+1}　{s}{i+1<step&&<span className="reg-completed">{c.completedStep}</span>}</button>)}</nav><p>{c.pilot}<br/>{c.maximum.replace('{max}',String(max))}<br/><br/>[CONDIȚII PILOT]</p></aside>
   <div className="card reg-card">
    <h1>{titles[step-1]}</h1><p className="reg-intro">{step===2?<><span className="reg-desktop">{c.fleetIntroDesktop}</span><span className="reg-mobile">{c.fleetIntro}</span></>:intros[step-1]}</p>
    {state.error&&<p className="alert alert-error" role="alert">{state.error}</p>}
    {sent.error&&<p className="alert alert-error" role="alert">{sent.error}</p>}
    {saved?.rejection_reason&&<p className="alert alert-error">{saved.rejection_reason}</p>}
    {waiting&&<p className="alert alert-ok" role="status">{c.sent}</p>}
    <form ref={form} action={action} className="reg-form">
     <section data-step="1" hidden={step!==1} className="reg-section">
      <label>{c.name}<input name="name" value={name} required minLength={2} maxLength={120} readOnly={!!saved} autoComplete="organization" onChange={e=>{setName(e.target.value);if(!touched)setSlug(slugify(e.target.value).slice(0,60));}}/></label>
      <label>{c.registrationNo}<input name="registration_no" defaultValue={saved?.registration_no??''} required minLength={2} maxLength={40} readOnly={!!saved}/></label>
      <label>{c.country}<select name="country" value={country} disabled={!!saved} onChange={e=>setCountry(e.target.value)}><option value="RO">România</option><option value="AT">Österreich</option><option value="DE">Deutschland</option></select></label>
      <label>{c.phone}<input name="contact_phone" type="tel" defaultValue={saved?.contact_phone??''} required minLength={6} maxLength={40} readOnly={!!saved} autoComplete="tel"/></label>
      <label>{c.licenseNo}<input name="license_no" defaultValue={saved?.license_no??''} required minLength={2} maxLength={60} readOnly={!!saved}/></label>
      {saved&&<p className="reg-note">{c.savedHint}</p>}
      <button type="button" className="btn btn-primary" onClick={()=>go(2)}>{c.nextFleet}</button>
     </section>
     <section data-step="2" hidden={step!==2} className="reg-section">
      <label className="reg-count">{c.count}<select name="declared_vehicles" required value={count} disabled={!!saved} onChange={e=>setCount(Number(e.target.value))}>{Array.from({length:max},(_,i)=><option key={i+1} value={i+1}>{i+1} {c.vehicles}</option>)}</select></label>
      <div className="reg-packages">{displayPackages.map(p=><div className={'reg-package '+(!saved&&p===selected||saved&&p.vehicles_from===saved.package.vehicles_from?'selected':'')} key={p.vehicles_from}><span className="reg-desktop">{p.vehicles_from===selected?.vehicles_from?c.yourPackage:c.monthlyPackage}</span><b>{p.vehicles_from}–{p.vehicles_to} {c.vehicles}</b><strong>{p.monthly_eur} {c.monthly}</strong></div>)}</div>
      <strong className="reg-commission">{c.commission}</strong><p className="reg-note">{c.money}</p>
      {saved&&<p className="reg-note">{c.companyPackage}: {saved.package.monthly_eur} {c.monthly}. {c.savedHint}</p>}
      <p className="reg-note reg-mobile">{c.pilot}, {c.maximum.replace('{max}',String(max))}.<br/>[CONDIȚII PILOT]</p>
      <div className="reg-step-actions"><button type="button" className="btn btn-primary" onClick={()=>go(3)} disabled={!selected}>{c.nextProfile}</button><button type="button" className="btn reg-back" onClick={()=>go(1)}>{c.back}</button></div>
     </section>
     <section data-step="3" hidden={step!==3} className="reg-section">
      <label>{c.slug}<input name="slug" pattern="[a-z0-9-]{2,60}" required value={slug} readOnly={!!saved} onChange={e=>{setTouched(true);setSlug(e.target.value.toLowerCase());}}/></label>
      <p className="reg-note">{saved?c.savedHint:c.slugHint}<br/>{c.preview}: {rootHint}/f/{slug||'…'}</p>
      <div className="reg-summary"><h2>{c.summary}</h2><p>{name}<br/>{country==='RO'?'România':country==='DE'?'Deutschland':'Österreich'} · {count} {c.vehicles}<br/>{selected?.monthly_eur} {c.monthly} {c.perCompany}<br/>{c.commission}</p><button type="button" className="reg-text-button" onClick={()=>go(1)}>{c.edit}</button></div>
      <div className="reg-summary"><h2>{c.fleet} · {completed} / {Math.max(count,vehicles.length)} {c.complete}</h2>
       {vehicles.map((v,i)=>{const gaps=[!v.has_year&&c.year,!v.has_exterior_photo&&c.exterior,!v.has_interior_photo&&c.interior,!v.has_insurance&&c.insurance].filter(Boolean);return <div className="reg-vehicle" key={v.id}><b>{v.label||`${c.vehicle} ${i+1}`}</b><p>{gaps.length?`${c.missing}: ${gaps.join(', ')}.`:c.complete}</p><Link className="reg-text-button" href={`/dispecerat/vehicule/${v.id}`}>{c.finishVehicle}</Link></div>})}
       {missing.map(n=><div className="reg-vehicle" key={n}><b>{c.vehicle} {n}</b><p>{c.missing}: {c.allMissing}.</p>{saved?<Link className="reg-text-button" href="/dispecerat/vehicule#vehicul-nou">{c.addVehicle}</Link>:<button className="reg-text-button" disabled={pending} type="submit">{pending?c.saving:c.addVehicle}</button>}</div>)}
      </div>
      {!saved&&<><label className="check"><input type="checkbox" name="terms" required/>{c.terms}</label><input type="hidden" name="expected_price" value={selected?.monthly_eur??''}/><p className="reg-note">{c.draftHint}</p></>}
      {!saved&&<button className="btn btn-primary" disabled>{c.send}</button>}
     </section>
    </form>
    {step===3&&<>
     {saved&&!waiting&&<form action={sendAction} className="reg-section"><input type="hidden" name="company_id" value={saved.id}/><button className="btn btn-primary" disabled={!ready||sending}>{sending?c.saving:c.send}</button></form>}
     <button type="button" className="btn reg-back" onClick={()=>go(2)}>{c.back}</button><p className="reg-note">{c.blocked}</p>
    </>}
   </div>
  </div>
 </main>;
}
