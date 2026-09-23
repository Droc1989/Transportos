'use server';
import { revalidatePath } from 'next/cache';
import { requirePlatformAdmin } from '@/lib/admin';
import { errorMessage,text } from '@/lib/form';
export type PackageState={error:string|null;saved:boolean};
export async function saveCatalog(_prev:PackageState,form:FormData):Promise<PackageState>{
 const {supabase}=await requirePlatformAdmin();let packages:unknown;
 try{packages=JSON.parse(text(form,'packages'));}catch{return {error:await errorMessage({message:'PACKAGE_CATALOG_INVALID'}),saved:false};}
 const {error}=await supabase.rpc('admin_save_vehicle_packages',{p_packages:packages});
 if(error)return {error:await errorMessage(error),saved:false};
 revalidatePath('/admin');revalidatePath('/inregistrare-firma');return {error:null,saved:true};
}
export async function saveCompanyPackage(_prev:PackageState,form:FormData):Promise<PackageState>{
 const {supabase}=await requirePlatformAdmin();const id=text(form,'company_id');
 const {error}=await supabase.rpc('admin_set_company_vehicle_package',{p_company_id:id,p_declared_vehicles:Number(form.get('declared_vehicles')),p_monthly_eur:Number(form.get('monthly_eur'))});
 if(error)return {error:await errorMessage(error),saved:false};
 revalidatePath(`/admin/firme/${id}`);revalidatePath('/admin');revalidatePath('/inregistrare-firma');return {error:null,saved:true};
}
