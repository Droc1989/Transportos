// Codurile de eroare întoarse de funcțiile SQL (în mesajul excepției).
export const DOMAIN_ERRORS = [
  'TRIP_NOT_FOUND', 'BOOKING_NOT_FOUND', 'FORBIDDEN', 'COMPANY_READ_ONLY',
  'TRIP_CLOSED', 'INVALID_SEGMENT', 'NOT_ENOUGH_SEATS', 'HOLD_EXPIRED', 'INVALID_POSITION',
  'TEMPLATE_NOT_FOUND', 'INVALID_ROUTE', 'DRIVER_ALREADY_LINKED', 'INVITE_INVALID',
  'TRIP_IN_PROGRESS', 'VEHICLE_TOO_SMALL', 'STOP_ORDER_INVALID', 'STOP_STATE_INVALID',
  'FEATURE_NOT_ENABLED', 'SITE_NOT_FOUND', 'REQUEST_LIMIT', 'INVALID_REQUEST',
] as const;
export type DomainError = (typeof DOMAIN_ERRORS)[number];

/** Extrage codul de domeniu dintr-o eroare Supabase/PostgREST, dacă există. */
export function toDomainError(message: string | undefined | null): DomainError | null {
  if (!message) return null;
  return DOMAIN_ERRORS.find((code) => message.includes(code)) ?? null;
}
