'use client';
import { useActionState,useState } from 'react';
import type { RegistrationCopy,VehiclePackage,SavedPackage } from '@/lib/registration-copy';
import {saveCatalog,saveCompanyPackage} from './actions';
export function CatalogEditor({copy:c,packages}:{copy:RegistrationCopy;packages:VehiclePackage[]}){
 const [rows,setRows]=useState(packages);const [state,action,pending]=useActionState(saveCatalog,{error:null,saved:false});
 function change(i:number,key:'vehicles_from'|'vehicles_to'|'monthly_eur',value:number){setRows(rows.map((r,j)=>j===i?{...r,[key]:value}:r));}
 return <form action={action} className="form" style={{maxWidth:'none'}}><h2 className="h2">{c.catalogTitle}</h2><p>{c.catalogHint}</p>
 {state.error&&<p role="alert" className="alert alert-error">{state.error}</p>}{state.saved&&!state.error&&<p role="status" className="alert alert-ok">{c.saved}</p>}
 <input type="hidden" name="packages" value={JSON.stringify(rows)}/>
 {rows.map((r,i)=><fieldset key={i}><div className="row"><label>{c.from}<input type="number" min={1} required value={r.vehicles_from} onChange={e=>change(i,'vehicles_from',Number(e.target.value))}/></label><label>{c.to}<input type="number" min={r.vehicles_from} required value={r.vehicles_to} onChange={e=>change(i,'vehicles_to',Number(e.target.value))}/></label></div><label>{c.price}<input type="number" min={0} step="0.01" required value={r.monthly_eur} onChange={e=>change(i,'monthly_eur',Number(e.target.value))}/></label><button type="button" className="btn" onClick={()=>setRows(rows.filter((_,j)=>i!==j))} disabled={rows.length===1||pending}>{c.remove}</button></fieldset>)}
 <button type="button" className="btn" disabled={pending} onClick={()=>{const n=Math.max(0,...rows.map(r=>r.vehicles_to))+1;setRows([...rows,{vehicles_from:n,vehicles_to:n,monthly_eur:0}]);}}>{c.add}</button><button className="btn btn-primary" disabled={pending}>{pending?c.saving:c.saveCatalog}</button></form>;
}
export function CompanyPackageEditor({copy:c,plan,companyId,max}:{copy:RegistrationCopy;plan:SavedPackage;companyId:string;max:number}){
 const [state,action,pending]=useActionState(saveCompanyPackage,{error:null,saved:false});
 return <form action={action} className="form"><h2 className="h2">{c.companyPackage}</h2><p><strong>{plan.vehicles_from}–{plan.vehicle_limit} {c.vehicles} · {plan.monthly_eur} {c.monthly} {c.perCompany}</strong></p><p>{c.companyHint}</p><input type="hidden" name="company_id" value={companyId}/>
 {state.error&&<p className="alert alert-error" role="alert">{state.error}</p>}{state.saved&&!state.error&&<p className="alert alert-ok" role="status">{c.saved}</p>}
 <label>{c.count}<input type="number" name="declared_vehicles" min={1} max={max} defaultValue={plan.declared_vehicles} required/></label><label>{c.price}<input type="number" min={0} step="0.01" name="monthly_eur" defaultValue={plan.monthly_eur} required/></label><button className="btn btn-primary" disabled={pending}>{pending?c.saving:c.saveCompany}</button></form>;
}
