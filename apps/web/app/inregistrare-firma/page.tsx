import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getRegistrationCopy } from '@/lib/i18n';
import type { SavedRegistration, VehiclePackage } from '@/lib/registration-copy';
import { CompanyForm } from './company-form';
import './registration.css';
export default async function RegisterCompanyPage(){
 const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();const {copy}=await getRegistrationCopy();
 if(!user)return <main className="login"><div className="card"><h1>{copy.title}</h1><p>{copy.needAccount}</p><p><Link className="btn btn-primary btn-link" href="/inregistrare?next=/inregistrare-firma">{copy.account}</Link></p><Link href="/login?next=/inregistrare-firma">{copy.haveAccount}</Link></div></main>;
 const {data:catalog,error}=await supabase.from('vehicle_package_catalog').select('id,vehicles_from,vehicles_to,monthly_eur').order('vehicles_from');
 if(error||!catalog?.length)return <main className="login"><p role="alert" className="alert alert-error">{copy.unavailable}</p></main>;
 const {data:member,error:memberError}=await supabase.from('company_members').select('company_id,role').eq('user_id',user.id).in('role',['OWNER','ADMIN','DISPATCHER']).limit(1).maybeSingle();
 if(memberError)throw memberError;
 let saved:SavedRegistration|null=null;
 if(member){
 const [company,plan,check]=await Promise.all([
 supabase.from('companies').select('id,name,slug,country,status,registration_no,license_no,contact_phone,submitted_at,rejection_reason').eq('id',member.company_id).single(),
 supabase.from('company_vehicle_packages').select('declared_vehicles,vehicles_from,vehicle_limit,monthly_eur').eq('company_id',member.company_id).single(),
 supabase.rpc('get_registration_checklist',{p_company_id:member.company_id})]);
 for(const r of [company,plan,check])if(r.error)throw r.error;
 if(!['PENDING_VERIFICATION','REJECTED'].includes(company.data!.status))redirect('/dispecerat');
 saved={...company.data!,package:plan.data!,vehicles:check.data.vehicles} as SavedRegistration;
 }
 return <CompanyForm copy={copy} packages={catalog as VehiclePackage[]} saved={saved} rootHint=""/>;
}
