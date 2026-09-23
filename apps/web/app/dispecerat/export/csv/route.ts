import { NextResponse, type NextRequest } from 'next/server';
import { toDomainError } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { getT } from '@/lib/i18n';
import { zonedLocalToUtc } from '@/lib/time';

type Row = {
  departure_at: string;
  trip_title: string;
  vehicle_label: string;
  booking_id: string;
  customer_name: string;
  customer_phone: string;
  passengers: number;
  from_name: string;
  to_name: string;
  price_cents: number | null;
  currency: string;
  payment_method: string;
  status: string;
  created_at: string;
};

/** Câmp CSV cu separator „;” (Excel în română/germană), protejat și de formule. */
function cell(value: unknown): string {
  let s = value === null || value === undefined ? '' : String(value);
  if (/^[=+\-@]/.test(s)) s = `'${s}`;
  return /[;"\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export async function GET(request: NextRequest) {
  const { supabase, companyId, timeZone } = await requireStaffCompany();
  const { tError } = await getT();
  const from = request.nextUrl.searchParams.get('from') ?? '';
  const to = request.nextUrl.searchParams.get('to') ?? '';
  const fromUtc = zonedLocalToUtc(`${from}T00:00`, timeZone);
  const toUtc = zonedLocalToUtc(`${to}T00:00`, timeZone);
  if (!fromUtc || !toUtc) return new NextResponse('Invalid dates', { status: 400 });
  const toExclusive = new Date(toUtc.getTime() + 24 * 3600 * 1000);

  const { data, error } = await supabase.rpc('export_bookings', {
    p_company_id: companyId,
    p_from: fromUtc.toISOString(),
    p_to: toExclusive.toISOString(),
  });
  if (error) return new NextResponse(tError(toDomainError(error.message)), { status: 403 });

  const local = new Intl.DateTimeFormat('sv-SE', { timeZone, dateStyle: 'short', timeStyle: 'short' });
  const header = ['plecare', 'cursa', 'vehicul', 'rezervare', 'client', 'telefon', 'persoane', 'de_la', 'pana_la',
                  'pret', 'moneda', 'plata', 'status', 'creata'];
  const lines = ((data ?? []) as Row[]).map((r) =>
    [local.format(new Date(r.departure_at)), r.trip_title, r.vehicle_label, r.booking_id, r.customer_name,
     r.customer_phone, r.passengers, r.from_name, r.to_name,
     r.price_cents === null ? '' : (r.price_cents / 100).toFixed(2).replace('.', ','), r.currency,
     r.payment_method, r.status, local.format(new Date(r.created_at))].map(cell).join(';'),
  );
  const csv = '\uFEFF' + [header.join(';'), ...lines].join('\r\n') + '\r\n';

  return new NextResponse(csv, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="rezervari_${from}_${to}.csv"`,
      'Cache-Control': 'no-store',
    },
  });
}
