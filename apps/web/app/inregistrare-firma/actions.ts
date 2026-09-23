'use server';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { errorMessage,text,type FormState } from '@/lib/form';
import { createClient } from '@/lib/supabase/server';
export async function registerCompany(_prev:FormState,form:FormData):Promise<FormState>{
 const supabase=await createClient();
 const {error}=await supabase.rpc('register_company_with_package',{
 p_name:text(form,'name'),p_slug:text(form,'slug').toLowerCase(),p_country:text(form,'country'),
 p_registration_no:text(form,'registration_no'),p_license_no:text(form,'license_no'),p_contact_phone:text(form,'contact_phone'),
 p_accept_terms:form.get('terms')==='on',p_declared_vehicles:Number(form.get('declared_vehicles')),p_expected_price:Number(form.get('expected_price'))});
 if(error)return {error:await errorMessage(error)};
 revalidatePath('/inregistrare-firma');redirect('/dispecerat/vehicule#vehicul-nou');
}
export async function sendCompanyReview(_prev:FormState,form:FormData):Promise<FormState>{
 const supabase=await createClient();const {error}=await supabase.rpc('submit_company_for_review',{p_company_id:text(form,'company_id')});
 if(error)return {error:await errorMessage(error)};
 revalidatePath('/inregistrare-firma');revalidatePath('/admin/aprobari');redirect('/inregistrare-firma');
}
