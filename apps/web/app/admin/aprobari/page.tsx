import Link from 'next/link';
import { requirePlatformAdmin } from '@/lib/admin';
import { setMinVehicleYear } from '../actions';

type Pending = {
  id: string; name: string; country: string; registration_no: string | null; license_no: string | null;
  contact_phone: string | null; contact_email: string | null; submitted_at: string | null;
  vehicles: number; vehicles_pending: number; below_min_year: number;
};

const date = new Intl.DateTimeFormat('ro-RO', { timeZone: 'Europe/Bucharest', dateStyle: 'medium', timeStyle: 'short' });

export default async function ApprovalsPage() {
  const { supabase } = await requirePlatformAdmin();
  const [pending, minYear] = await Promise.all([
    supabase.rpc('admin_pending_companies'),
    supabase.rpc('min_vehicle_year'),
  ]);
  if (pending.error) throw pending.error;
  const rows = (pending.data ?? []) as Pending[];

  return (
    <>
      <h1>De aprobat</h1>
      <p className="lead">Firme noi care au trimis cererea și microbuze noi ale firmelor active.</p>
      <div className="split">
        <section className="card">
          {rows.length === 0 ? <p>Nimic de aprobat acum.</p> : (
            <table className="table">
              <thead><tr><th>Firma</th><th>Date</th><th>Microbuze</th><th>Trimisă</th></tr></thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td><Link href={`/admin/firme/${r.id}`}><strong>{r.name}</strong></Link> <span className="meta">{r.country}</span></td>
                    <td className="meta">CUI {r.registration_no ?? '—'} · licență {r.license_no ?? '—'}<br />{r.contact_phone} · {r.contact_email}</td>
                    <td>
                      {r.vehicles_pending} de verificat din {r.vehicles}
                      {r.below_min_year > 0 && <div className="old-year">{r.below_min_year} mai vechi de {minYear.data as number}</div>}
                    </td>
                    <td className="meta">{r.submitted_at ? date.format(new Date(r.submitted_at)) : 'firmă activă'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
        <form action={setMinVehicleYear} className="form">
          <fieldset>
            <legend>Anul minim al microbuzelor</legend>
            <label>Microbuzele mai vechi apar marcate la aprobare<input name="year" type="number" min={1980} max={2100} defaultValue={minYear.data as number} /></label>
          </fieldset>
          <button className="btn btn-primary">Salvează</button>
        </form>
      </div>
    </>
  );
}
