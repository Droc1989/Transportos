import { CompanyPackagePanel } from '../../_packages/panels';
import { notFound } from 'next/navigation';
import { requirePlatformAdmin } from '@/lib/admin';
import { ActionForm } from '../../../dispecerat/_components/action-form';
import { ShareButton } from '../../../dispecerat/_components/share-button';
import { FEATURE_LABELS, type VehicleFeature } from '@transportos/shared';
import { createOwnerInvite, reviewCompany, reviewVehicle, setFeature, updateSubscription } from '../../actions';

type Company = {
  id: string; name: string; slug: string; country: string; status: string; registration_no: string | null;
  license_no: string | null; contact_phone: string | null; contact_email: string | null; submitted_at: string | null;
  terms_accepted_at: string | null; rejection_reason: string | null;
};
type FleetRow = {
  id: string; label: string; plate: string | null; seats: number; manufacture_year: number | null; features: string[];
  luggage_pieces: number | null; luggage_kg: number | null; rca_valid_until: string | null; passenger_insurance_until: string | null;
  insurance_declared_at: string | null; approval_status: string; approval_note: string | null;
  vehicle_photos: { id: string; kind: string; url: string }[];
};
const d = new Intl.DateTimeFormat('ro-RO', { timeZone: 'Europe/Bucharest', dateStyle: 'medium' });
type Subscription = { plan_id: string; status: string; current_period_end: string | null };

const SUB_STATUSES = ['TRIAL', 'ACTIVE', 'PAST_DUE', 'READ_ONLY', 'CANCELLED'];

export default async function AdminCompanyPage({ params, searchParams }: {
  params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; reviewed?: string }>;
}) {
  const { id } = await params;
  const { error: pageError, reviewed } = await searchParams;
  const { supabase } = await requirePlatformAdmin();

  const [company, sub, plans, features, planFeatures, overrides, settings, fleet, minYear] = await Promise.all([
    supabase.from('companies').select('id, name, slug, country, status, registration_no, license_no, contact_phone, contact_email, submitted_at, terms_accepted_at, rejection_reason').eq('id', id).maybeSingle<Company>(),
    supabase.from('company_subscriptions').select('plan_id, status, current_period_end').eq('company_id', id).maybeSingle<Subscription>(),
    supabase.from('plans').select('id, name').order('id').returns<{ id: string; name: string }[]>(),
    supabase.from('features').select('key, description').order('key').returns<{ key: string; description: string }[]>(),
    supabase.from('plan_features').select('plan_id, feature_key').returns<{ plan_id: string; feature_key: string }[]>(),
    supabase.from('company_feature_overrides').select('feature_key, enabled').eq('company_id', id)
      .returns<{ feature_key: string; enabled: boolean }[]>(),
    supabase.from('company_settings').select('show_on_public_map').eq('company_id', id).maybeSingle<{ show_on_public_map: boolean }>(),
    supabase.from('vehicles').select('id, label, plate, seats, manufacture_year, features, luggage_pieces, luggage_kg, rca_valid_until, passenger_insurance_until, insurance_declared_at, approval_status, approval_note, vehicle_photos(id, kind, url)')
      .eq('company_id', id).order('label').returns<FleetRow[]>(),
    supabase.rpc('min_vehicle_year'),
  ]);
  for (const r of [company, sub, plans, features, planFeatures, overrides, settings, fleet]) if (r.error) throw r.error;
  const min = (minYear.data as number | null) ?? 2012;
  if (!company.data) notFound();

  const c = company.data;
  const planId = sub.data?.plan_id ?? '';
  const inPlan = new Set((planFeatures.data ?? []).filter((pf) => pf.plan_id === planId).map((pf) => pf.feature_key));
  const override = new Map((overrides.data ?? []).map((o) => [o.feature_key, o.enabled]));

  return (
    <>
      <h1>{c.name}</h1><CompanyPackagePanel id={id} />
      <p className="lead">
        {c.slug} · {c.country} · stare: <strong>{c.status}</strong> · harta publică: {settings.data?.show_on_public_map ? 'acceptată de firmă' : 'neacceptată'}
      </p>
      {pageError && <p className="alert alert-error" role="alert">{pageError}</p>}
      {reviewed && <p className="alert alert-ok" role="status">Decizia a fost salvată; patronul primește emailul.</p>}

      <section className="card" style={{ marginBottom: 16 }}>
        <h2 className="h2">Înscriere</h2>
        <p className="meta" style={{ marginTop: 0 }}>
          CUI {c.registration_no ?? '—'} · licență {c.license_no ?? '—'} · {c.contact_phone ?? '—'} · {c.contact_email ?? '—'}<br />
          Termeni acceptați: {c.terms_accepted_at ? d.format(new Date(c.terms_accepted_at)) : 'nu'} ·
          Cerere trimisă: {c.submitted_at ? d.format(new Date(c.submitted_at)) : 'nu'}
          {c.rejection_reason ? ` · Respinsă: ${c.rejection_reason}` : ''}
        </p>

        <table className="table">
          <thead><tr><th>Microbuz</th><th>An</th><th>Condiții</th><th>Asigurări</th><th>Poze</th><th>Decizie</th></tr></thead>
          <tbody>
            {(fleet.data ?? []).map((v) => (
              <tr key={v.id}>
                <td><strong className="plate">{v.label}</strong><div className="meta">{v.plate} · {v.seats} locuri</div>
                  <span className={`badge badge-${v.approval_status}`}>{v.approval_status}</span>
                  {v.approval_note && <div className="meta">{v.approval_note}</div>}</td>
                <td className={v.manufacture_year !== null && v.manufacture_year < min ? 'old-year' : undefined}>
                  {v.manufacture_year ?? '—'}{v.manufacture_year !== null && v.manufacture_year < min ? ` (sub ${min})` : ''}
                </td>
                <td><div className="feature-list">{v.features.map((f) => <span key={f}>{FEATURE_LABELS.ro[f as VehicleFeature] ?? f}</span>)}</div>
                  {v.luggage_pieces !== null && <div className="meta">bagaj: {v.luggage_pieces} buc. / {v.luggage_kg ?? '—'} kg</div>}</td>
                <td className="meta">RCA: {v.rca_valid_until ? d.format(new Date(v.rca_valid_until)) : '—'}<br />
                  Pasageri: {v.passenger_insurance_until ? d.format(new Date(v.passenger_insurance_until)) : '—'}<br />
                  {v.insurance_declared_at ? `declarat ${d.format(new Date(v.insurance_declared_at))}` : 'nedeclarat'}</td>
                <td><div className="photo-grid" style={{ gridTemplateColumns: 'repeat(2, 90px)' }}>
                  {v.vehicle_photos.map((p) => <a key={p.id} href={p.url} target="_blank" rel="noreferrer"><img src={p.url} alt={p.kind} title={p.kind} /></a>)}
                </div></td>
                <td>
                  <form action={reviewVehicle} className="actions" style={{ flexDirection: 'column', alignItems: 'stretch' }}>
                    <input type="hidden" name="company_id" value={c.id} /><input type="hidden" name="vehicle_id" value={v.id} />
                    <input name="note" placeholder="Notă (obligatorie la respingere)" maxLength={1000} />
                    <div className="actions">
                      <button className="btn btn-small" name="approve" value="true">Aprobă</button>
                      <button className="btn btn-small" name="approve" value="false">Respinge</button>
                    </div>
                  </form>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {c.status !== 'ACTIVE' && c.submitted_at && (
          <form action={reviewCompany} className="actions" style={{ justifyContent: 'flex-start', marginTop: 12 }}>
            <input type="hidden" name="company_id" value={c.id} />
            <input name="reason" placeholder="Motiv (obligatoriu la respingere)" maxLength={1000} style={{ minWidth: 320 }} />
            <button className="btn btn-primary" name="approve" value="true">Aprobă firma</button>
            <button className="btn btn-small" name="approve" value="false">Respinge firma</button>
          </form>
        )}
      </section>

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
