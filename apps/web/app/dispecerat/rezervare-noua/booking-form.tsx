'use client';

import { useActionState, useMemo, useState } from 'react';
import type { PaymentMethod } from '@transportos/shared';
import { createBooking, type BookingFormState } from './actions';

export type TripOption = {
  id: string;
  label: string;
  points: { seq: number; name: string }[];
};

type Labels = Record<
  | 'customer' | 'phone' | 'name' | 'passengers' | 'trip' | 'from' | 'to'
  | 'pickupAddress' | 'pickupNotes' | 'payment' | 'submit' | 'saving',
  string
>;

export function BookingForm({
  trips,
  labels,
  paymentLabels,
  idempotencyKey,
  defaults,
}: {
  trips: TripOption[];
  labels: Labels;
  paymentLabels: Record<PaymentMethod, string>;
  idempotencyKey: string;
  defaults?: { name: string; phone: string; passengers: number; requestId: string };
}) {
  const [state, action, pending] = useActionState<BookingFormState, FormData>(createBooking, { error: null });
  const [tripId, setTripId] = useState(trips[0]?.id ?? '');
  const points = useMemo(() => trips.find((tr) => tr.id === tripId)?.points ?? [], [trips, tripId]);
  const [fromSeq, setFromSeq] = useState(0);
  const lastSeq = points.length ? points[points.length - 1]!.seq : 0;

  return (
    <form action={action} className="form">
      <input type="hidden" name="idempotency_key" value={idempotencyKey} />
      {defaults?.requestId && <input type="hidden" name="request_id" value={defaults.requestId} />}
      {state.error && <p role="alert" className="alert alert-error">{state.error}</p>}

      <fieldset>
        <legend>{labels.customer}</legend>
        <label>
          {labels.phone}
          <input name="phone" type="tel" autoComplete="off" required placeholder="+40 7…" defaultValue={defaults?.phone} />
        </label>
        <div className="row">
          <label>
            {labels.name}
            <input name="name" required defaultValue={defaults?.name} />
          </label>
          <label>
            {labels.passengers}
            <input name="passengers" type="number" min={1} max={20} defaultValue={defaults?.passengers ?? 1} required />
          </label>
        </div>
      </fieldset>

      <fieldset>
        <legend>{labels.trip}</legend>
        <label>
          {labels.trip}
          <select name="trip_id" value={tripId} onChange={(e) => { setTripId(e.target.value); setFromSeq(0); }}>
            {trips.map((tr) => (
              <option key={tr.id} value={tr.id}>{tr.label}</option>
            ))}
          </select>
        </label>
        <div className="row">
          <label>
            {labels.from}
            <select name="from_seq" value={fromSeq} onChange={(e) => setFromSeq(Number(e.target.value))}>
              {points.slice(0, -1).map((p) => (
                <option key={p.seq} value={p.seq}>{p.name}</option>
              ))}
            </select>
          </label>
          <label>
            {labels.to}
            <select name="to_seq" defaultValue={lastSeq} key={`${tripId}-${fromSeq}`}>
              {points.filter((p) => p.seq > fromSeq).map((p) => (
                <option key={p.seq} value={p.seq}>{p.name}</option>
              ))}
            </select>
          </label>
        </div>
        <label>
          {labels.pickupAddress}
          <input name="pickup_address" />
        </label>
        <label>
          {labels.pickupNotes}
          <textarea name="pickup_notes" />
        </label>
      </fieldset>

      <fieldset>
        <legend>{labels.payment}</legend>
        <select name="payment_method" defaultValue="CASH_TO_DRIVER" aria-label={labels.payment}>
          {(Object.keys(paymentLabels) as PaymentMethod[]).map((m) => (
            <option key={m} value={m}>{paymentLabels[m]}</option>
          ))}
        </select>
      </fieldset>

      <button className="btn btn-primary" disabled={pending}>
        {pending ? labels.saving : labels.submit}
      </button>
    </form>
  );
}
