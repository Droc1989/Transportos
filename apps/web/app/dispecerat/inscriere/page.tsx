import {redirect} from 'next/navigation';
import {requireStaffCompany} from '@/lib/company';
export default async function RegistrationPage(){
 const {isActive}=await requireStaffCompany({allowPending:true});
 redirect(isActive?'/dispecerat':'/inregistrare-firma');
}
