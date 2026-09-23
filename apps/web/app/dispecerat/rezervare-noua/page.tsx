import { randomUUID } from 'node:crypto';
import { PAYMENT_METHODS, type PaymentMethod } from '@transportos/shared';
import { requireStaffCompany } from '@/lib/company';
import { getT, type MessageKey } from '@/lib/i18n';
import { BookingForm, type TripOption } from './booking-form';

type Row = {
  id: string;
  title: string;
  departure_at: string;
  vehicles: { label: string } | null;
  trip_route_points: { seq: number; name: string }[];
};

export default async function NewBookingPage({
  searchParams,
}: {
  searchParams: Promise<{ name?: string; phone?: string; pax?: string; request?: string }>;
}) {
  const prefill = await searchParams;
  const { supabase, companyId } = await requireStaffCompany();
  const { t, locale } = await getT();

  const { data, error } = await supabase
    .from('trips')
    .select('id, title, departure_at, vehicles(label), trip_route_points(seq, name)')
    .eq('company_id', companyId)
    .eq('status', 'PLANNED')
    .gte('departure_at', new Date().toISOString())
    .order('departure_at')
    .limit(50)
    .returns<Row[]>();
  if (error) throw error;

  const fmt = new Intl.DateTimeFormat(locale === 'de' ? 'de-AT' : 'ro-RO', {
    weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
  });
  const trips: TripOption[] = (data ?? [])
    .filter((tr) => tr.trip_route_points.length >= 2)
    .map((tr) => ({
      id: tr.id,
      label: `${fmt.format(new Date(tr.departure_at))} · ${tr.vehicles?.label ?? ''} · ${tr.title}`,
      points: [...tr.trip_route_points].sort((a, b) => a.seq - b.seq),
    }));

  const paymentLabels = Object.fromEntries(
    PAYMENT_METHODS.map((m) => [m, t(`payment.${m}` as MessageKey)]),
  ) as Record<PaymentMethod, string>;

  return (
    <>
      <h1>{t('booking.title')}</h1>
      {trips.length === 0 ? (
        <p className="card">{t('booking.noTrips')}</p>
      ) : (
        <BookingForm
          trips={trips}
          idempotencyKey={randomUUID()}
          defaults={{
            name: prefill.name ?? '',
            phone: prefill.phone ?? '',
            passengers: Math.min(Math.max(Number(prefill.pax) || 1, 1), 20),
            requestId: prefill.request ?? '',
          }}
          paymentLabels={paymentLabels}
          labels={{
            customer: t('booking.customer'),
            phone: t('booking.phone'),
            name: t('booking.name'),
            passengers: t('booking.passengers'),
            trip: t('booking.trip'),
            from: t('booking.from'),
            to: t('booking.to'),
            pickupAddress: t('booking.pickupAddress'),
            pickupNotes: t('booking.pickupNotes'),
            payment: t('booking.payment'),
            submit: t('booking.submit'),
            saving: t('booking.saving'),
          }}
        />
      )}
    </>
  );
}
