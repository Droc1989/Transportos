import { notFound } from 'next/navigation';
import { requirePlatformAdmin } from '@/lib/admin';
import { ActionForm } from '../../../dispecerat/_components/action-form';
import { ShareButton } from '../../../dispecerat/_components/share-button';
import { createOwnerInvite, setFeature, updateSubscription } from '../../actions';

type Company = { id: string; name: string; slug: string; country: string; status: string };
type Subscription = { plan_id: string; status: string; current_period_end: string | null };

const SUB_STATUSES = ['TRIAL', 'ACTIVE', 'PAST_DUE', 'READ_ONLY', 'CANCELLED'];

export default async function AdminCompanyPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requirePlatformAdmin();

  const [company, sub, plans, features, planFeatures, overrides, settings] = await Promise.all([
    supabase.from('companies').select('id, name, slug, country, status').eq('id', id).maybeSingle<Company>(),
    supabase.from('company_subscriptions').select('plan_id, status, current_period_end').eq('company_id', id).maybeSingle<Subscription>(),
    supabase.from('plans').select('id, name').order('id').returns<{ id: string; name: string }[]>(),
    supabase.from('features').select('key, description').order('key').returns<{ key: string; description: string }[]>(),
    supabase.from('plan_features').select('plan_id, feature_key').returns<{ plan_id: string; feature_key: string }[]>(),
    supabase.from('company_feature_overrides').select('feature_key, enabled').eq('company_id', id)
      .returns<{ feature_key: string; enabled: boolean }[]>(),
    supabase.from('company_settings').select('show_on_public_map').eq('company_id', id).maybeSingle<{ show_on_public_map: boolean }>(),
  ]);
  for (const r of [company, sub, plans, features, planFeatures, overrides, settings]) if (r.error) throw r.error;
  if (!company.data) notFound();

  const c = company.data;
  const planId = sub.data?.plan_id ?? '';
  const inPlan = new Set((planFeatures.data ?? []).filter((pf) => pf.plan_id === planId).map((pf) => pf.feature_key));
  const override = new Map((overrides.data ?? []).map((o) => [o.feature_key, o.enabled]));

  return (
    <>
      <h1>{c.name}</h1>
      <p className="lead">
        {c.slug} · {c.country} · harta publică: {settings.data?.show_on_public_map ? 'acceptată de firmă' : 'neacceptată'}
      </p>

      <div className="split">
        <section className="card">
          <h2 className="h2">Funcții</h2>
          <table className="table">
            <thead><tr><th>Funcție</th><th>Stare</th><th /></tr></thead>
            <tbody>
              {(features.data ?? []).map((f) => {
                const o = override.get(f.key);
                const active = o ?? inPlan.has(f.key);
                return (
                  <tr key={f.key}>
                    <td>{f.description}<div className="meta">{f.key}</div></td>
                    <td>
                      <strong>{active ? 'pornită' : 'oprită'}</strong>
                      <div className="meta">{o === undefined ? 'din plan' : 'excepție setată de tine'}</div>
                    </td>
                    <td>
                      <div className="actions">
                        {(['on', 'off', 'plan'] as const).map((mode) => (
                          <form key={mode} action={setFeature}>
                            <input type="hidden" name="company_id" value={c.id} />
                            <input type="hidden" name="feature_key" value={f.key} />
                            <input type="hidden" name="mode" value={mode} />
                            <button
                              className="btn btn-small"
                              disabled={(mode === 'plan' && o === undefined) || (mode === 'on' && o === true) || (mode === 'off' && o === false)}
                            >
                              {mode === 'on' ? 'Pornește' : mode === 'off' ? 'Oprește' : 'Ca în plan'}
                            </button>
                          </form>
                        ))}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </section>

        <div className="list">
          <ActionForm action={updateSubscription} submitLabel="Salvează" pendingLabel="Se salvează…">
            <input type="hidden" name="company_id" value={c.id} />
            <fieldset>
              <legend>Abonament</legend>
              <label>
                Plan
                <select name="plan_id" defaultValue={planId}>
                  {(plans.data ?? []).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </label>
              <div className="row">
                <label>
                  Stare
                  <select name="status" defaultValue={sub.data?.status ?? 'TRIAL'}>
                    {SUB_STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
                  </select>
                </label>
                <label>
                  Plătit până la
                  <input type="date" name="period_end" defaultValue={sub.data?.current_period_end ?? ''} />
                </label>
              </div>
              <label>
                Firma
                <select name="company_status" defaultValue={c.status}>
                  <option value="ACTIVE">Activă</option>
                  <option value="PENDING_VERIFICATION">În verificare</option>
                  <option value="SUSPENDED">Suspendată</option>
                </select>
              </label>
              <p className="meta" style={{ margin: 0 }}>
                READ_ONLY: firma își vede datele, dar nu mai face rezervări sau curse noi. Cursele pornite continuă.
              </p>
            </fieldset>
          </ActionForm>

          <section className="card">
            <h2 className="h2">Proprietarul firmei</h2>
            <p className="meta">Generează un cod și trimite-l patronului. Îl introduce pe /invitatie după ce își face cont.</p>
            <ShareButton
              action={createOwnerInvite}
              fields={{ company_id: c.id }}
              mono
              labels={{
                button: 'Generează cod de proprietar',
                title: 'Cod de invitație',
                help: 'Merge o singură dată și expiră în 7 zile.',
                copy: 'Copiază',
                copied: 'Copiat',
                whatsapp: 'Trimite pe WhatsApp',
                message: 'Bună! Firma ta a fost creată în TransportOS. Creează-ți cont și introdu codul:',
              }}
            />
          </section>
        </div>
      </div>
    </>
  );
}
