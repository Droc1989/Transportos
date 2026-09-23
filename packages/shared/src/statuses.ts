// Statusurile canonice. Sursa de adevăr sunt tipurile enum din
// supabase/migrations/20260923000100_extensions_and_types.sql.
// scripts/check-enums.mjs verifică în CI că listele de aici sunt identice.

export const SERVICE_TYPES = ['PASSENGER', 'PARCEL', 'VEHICLE', 'CARGO', 'PRIVATE_TRANSFER'] as const;
export type ServiceType = (typeof SERVICE_TYPES)[number];

export const VEHICLE_STATUSES = [
  'AVAILABLE', 'ASSIGNED', 'EN_ROUTE', 'PICKUP', 'IN_SERVICE', 'BREAK',
  'STANDBY', 'MAINTENANCE', 'BREAKDOWN', 'OFFLINE', 'EMERGENCY',
] as const;
export type VehicleStatus = (typeof VEHICLE_STATUSES)[number];

export const BOOKING_STATUSES = [
  'REQUESTED', 'HELD', 'CONFIRMED', 'DRIVER_ASSIGNED', 'APPROACHING',
  'ARRIVED', 'ON_BOARD', 'COMPLETED', 'CANCELLED', 'NO_SHOW', 'MISSED_PICKUP',
] as const;
export type BookingStatus = (typeof BOOKING_STATUSES)[number];

export const TRIP_EVENT_TYPES = [
  'TRIP_STARTED', 'PICKUP_APPROACHING', 'ARRIVED_AT_PICKUP', 'PASSENGER_ON_BOARD',
  'PICKUP_AT_RISK', 'PICKUP_MISSED', 'ROUTE_DEVIATION', 'BREAK_STARTED',
  'BREAK_ENDED', 'FUEL_ADDED', 'INCIDENT', 'TRIP_COMPLETED',
] as const;
export type TripEventType = (typeof TRIP_EVENT_TYPES)[number];

export const TRIP_STATUSES = ['PLANNED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'] as const;
export type TripStatus = (typeof TRIP_STATUSES)[number];

export const MEMBER_ROLES = ['OWNER', 'ADMIN', 'DISPATCHER', 'DRIVER'] as const;
export type MemberRole = (typeof MEMBER_ROLES)[number];

export const SUBSCRIPTION_STATUSES = ['TRIAL', 'ACTIVE', 'PAST_DUE', 'READ_ONLY', 'CANCELLED'] as const;
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

export const PAYMENT_METHODS = ['CASH_TO_DRIVER', 'CARD', 'PAYMENT_LINK', 'DEPOSIT_AND_REST'] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

export const STOP_KINDS = ['PICKUP', 'DROPOFF'] as const;
export type StopKind = (typeof STOP_KINDS)[number];

export const STOP_STATUSES = ['PLANNED', 'APPROACHING', 'ARRIVED', 'DONE', 'SKIPPED'] as const;
export type StopStatus = (typeof STOP_STATUSES)[number];

/** Numele tipului din SQL pentru fiecare listă, folosit de scripts/check-enums.mjs. */
export const SQL_ENUMS = {
  service_type: SERVICE_TYPES,
  vehicle_status: VEHICLE_STATUSES,
  booking_status: BOOKING_STATUSES,
  trip_event_type: TRIP_EVENT_TYPES,
  trip_status: TRIP_STATUSES,
  member_role: MEMBER_ROLES,
  subscription_status: SUBSCRIPTION_STATUSES,
  payment_method: PAYMENT_METHODS,
  stop_kind: STOP_KINDS,
  stop_status: STOP_STATUSES,
} as const;
