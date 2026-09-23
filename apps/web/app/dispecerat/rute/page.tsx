import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { RouteBuilder, type Place } from './route-builder';

type Template = {
  id: string;
  name: string;
  route_template_points: { seq: number; places: { name: string } | null }[];
};

export default async function RoutesPage() {
  const { supabase, companyId } = await requireStaffCompany();
  const { t } = await getT();

  const [{ data: templates, error: tErr }, { data: places, error: pErr }] = await Promise.all([
    supabase
      .from('route_templates')
      .select('id, name, route_template_points(seq, places(name))')
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
