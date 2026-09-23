import Link from 'next/link';
import { requirePlatformAdmin } from '@/lib/admin';
import { ActionForm } from '../dispecerat/_components/action-form';
import { createCompany } from './actions';

type CompanyRow = {
  id: string;
  name: string;
  country: string;
  status: string;
  plan_id: string | null;
  subscription: string | null;
  period_end: string | null;
  vehicles: number;
  billable: number;
  members: number;
  last_activity: string | null;
};
type Plan = { id: string; name: string; price_cents_per_vehicle: number; min_monthly_price_cents: number };

const eur = new Intl.NumberFormat('ro-RO', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 });
const date = new Intl.DateTimeFormat('ro-RO', { timeZone: 'Europe/Bucharest', dateStyle: 'medium' });

/** Venit lunar estimat: vehicule facturabile × preț, cel puțin minimul planului. */
function monthlyCents(row: CompanyRow, plans: Map<string, Plan>) {
  const plan = row.plan_id ? plans.get(row.plan_id) : undefined;
  if (!plan || !['ACTIVE', 'PAST_DUE'].includes(row.subscription ?? '')) return 0;
  return Math.max(row.billable * plan.price_cents_per_vehicle, plan.min_monthly_price_cents);
}

export default async function AdminHome() {
  const { supabase } = await requirePlatformAdmin();
  const [companies, plans] = await Promise.all([
    supabase.rpc('admin_list_companies'),
    supabase.from('plans').select('id, name, price_cents_per_vehicle, min_monthly_price_cents').order('id').returns<Plan[]>(),
  ]);
  if (companies.error) throw companies.error;
  if (plans.error) throw plans.error;

  const rows = (companies.data ?? []) as CompanyRow[];
  const planMap = new Map((plans.data ?? []).map((p) => [p.id, p]));
  const mrr = rows.reduce((s, r) => s + monthlyCents(r, planMap), 0);
  const paying = rows.filter((r) => monthlyCents(r, planMap) > 0).length;

  return (
    <>
      <h1>Firme</h1>
      <div className="kpis">
        <div className="card"><span className="meta">Firme plătitoare</span><strong>{paying}</strong><span className="meta">din {rows.length}</span></div>
        <div className="card"><span className="meta">Vehicule facturabile</span><strong>{rows.reduce((s, r) => s + r.billable, 0)}</strong></div>
        <div className="card kpi-accent"><span>Venit lunar estimat</span><strong>{eur.format(mrr / 100)}</strong><span>fără TVA</span></div>
      </div>

      <div className="split">
        <section className="card">
          <table className="table">
            <thead>
              <tr><th>Firma</th><th>Plan</th><th>Abonament</th><th>Vehicule</th><th>Ultima activitate</th></tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className={r.status === 'SUSPENDED' ? 'muted' : undefined}>
                  <td><Link href={`/admin/firme/${r.id}`}><strong>{r.name}</strong></Link> <span className="meta">{r.country}</span></td>
                  <td>{r.plan_id ?? '—'}</td>
                  <td>
                    {r.subscription ?? '—'}
                    {r.period_end ? <div className="meta">până la {date.format(new Date(r.period_end))}</div> : null}
                  </td>
                  <td>{r.billable}<span className="meta"> / {r.vehicles}</span></td>
                  <td className="meta">{r.last_activity ? date.format(new Date(r.last_activity)) : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>

        <ActionForm action={createCompany} submitLabel="Creează firma" pendingLabel="Se creează…">
          <fieldset>
            <legend>Firmă nouă</legend>
            <label>Nume<input name="name" required maxLength={120} placeholder="Transport Exemplu SRL" /></label>
            <label>Identificator scurt<input name="slug" required pattern="[a-z0-9-]{2,60}" placeholder="transport-exemplu" /></label>
            <div className="row">
              <label>
                Țara
                <select name="country" defaultValue="RO">
                  <option value="RO">România</option>
                  <option value="AT">Austria</option>
                  <option value="DE">Germania</option>
                </select>
              </label>
              <label>
                Plan
                <select name="plan_id" defaultValue="PILOT">
                  {(plans.data ?? []).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </label>
            </div>
          </fieldset>
        </ActionForm>
      </div>
    </>
  );
}
