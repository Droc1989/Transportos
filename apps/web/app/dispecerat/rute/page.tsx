import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { deleteRoutePrice, saveRoutePrice } from './actions';
import { RouteBuilder, type Place } from './route-builder';

type Template = {
  id: string;
  name: string;
  route_template_points: { seq: number; places: { name: string } | null }[];
  route_template_prices: { from_seq: number; to_seq: number; price_cents: number }[];
};

export default async function RoutesPage() {
  const { supabase, companyId } = await requireStaffCompany();
  const { t } = await getT();

  const [{ data: templates, error: tErr }, { data: places, error: pErr }] = await Promise.all([
    supabase
      .from('route_templates')
      .select('id, name, route_template_points(seq, places(name)), route_template_prices(from_seq, to_seq, price_cents)')
      .eq('company_id', companyId)
      .order('name')
      .returns<Template[]>(),
    supabase.from('places').select('id, name, country').order('name').returns<Place[]>(),
  ]);
  if (tErr) throw tErr;
  if (pErr) throw pErr;

  return (
    <>
      <h1>{t('routes.title')}</h1>
      <p className="lead">{t('routes.intro')}</p>
      <div className="split">
        <section className="card">
          {(templates ?? []).length === 0 ? (
            <p>{t('routes.empty')}</p>
          ) : (
            <ul className="list" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
              {(templates ?? []).map((tpl) => (
                <li key={tpl.id} className="route">
                  <strong>{tpl.name}</strong>
                  <div className="meta">
                    {[...tpl.route_template_points]
                      .sort((a, b) => a.seq - b.seq)
                      .map((p) => p.places?.name)
                      .join(' → ')}
                  </div>
                  <details style={{ marginTop: 6 }}>
                    <summary className="meta" style={{ cursor: 'pointer' }}>{t('prices.title')} ({tpl.route_template_prices.length})</summary>
                    <p className="meta">{t('prices.help')}</p>
                    {(() => {
                      const points = [...tpl.route_template_points].sort((a, b) => a.seq - b.seq);
                      const name = (seq: number) => points.find((p) => p.seq === seq)?.places?.name ?? String(seq);
                      return (
                        <>
                          <table className="table">
                            <tbody>
                              {[...tpl.route_template_prices].sort((a, b) => a.from_seq - b.from_seq || a.to_seq - b.to_seq).map((p) => (
                                <tr key={`${p.from_seq}-${p.to_seq}`}>
                                  <td>{name(p.from_seq)} → {name(p.to_seq)}</td>
                                  <td><strong>{(p.price_cents / 100).toFixed(2)} €</strong></td>
                                  <td>
                                    <form action={deleteRoutePrice}>
                                      <input type="hidden" name="template_id" value={tpl.id} />
                                      <input type="hidden" name="from_seq" value={p.from_seq} />
                                      <input type="hidden" name="to_seq" value={p.to_seq} />
                                      <button className="btn btn-small">{t('prices.remove')}</button>
                                    </form>
                                  </td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                          <form action={saveRoutePrice} className="inline" style={{ flexWrap: 'wrap', marginTop: 8 }}>
                            <input type="hidden" name="template_id" value={tpl.id} />
                            <select name="from_seq" aria-label={t('prices.from')}>
                              {points.slice(0, -1).map((p) => <option key={p.seq} value={p.seq}>{p.places?.name}</option>)}
                            </select>
                            <select name="to_seq" aria-label={t('prices.to')} defaultValue={points.at(-1)?.seq}>
                              {points.slice(1).map((p) => <option key={p.seq} value={p.seq}>{p.places?.name}</option>)}
                            </select>
                            <input name="price" inputMode="decimal" required placeholder={t('prices.price')} style={{ width: 110 }} />
                            <button className="btn btn-small">{t('prices.add')}</button>
                          </form>
                        </>
                      );
                    })()}
                  </details>
                </li>
              ))}
            </ul>
          )}
        </section>
        <RouteBuilder
          places={places ?? []}
          labels={{
            name: t('routes.name'),
            points: t('routes.points'),
            pick: t('routes.pick'),
            add: t('common.add'),
            remove: t('common.remove'),
            up: t('common.up'),
            down: t('common.down'),
            create: t('routes.create'),
            saving: t('common.saving'),
          }}
        />
      </div>
    </>
  );
}
