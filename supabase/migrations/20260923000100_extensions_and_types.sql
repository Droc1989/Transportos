-- 0100 — Extensii și tipuri canonice
-- Statusurile de aici sunt sursa de adevăr. Trebuie să rămână identice cu
-- packages/shared/src/statuses.ts (verificat în CI de scripts/check-enums.mjs).

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists btree_gist with schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;

-- Tipuri de serviciu (master plan §6)
create type public.service_type as enum (
  'PASSENGER', 'PARCEL', 'VEHICLE', 'CARGO', 'PRIVATE_TRANSFER'
);

-- Statusuri vehicul (master plan §8)
create type public.vehicle_status as enum (
  'AVAILABLE', 'ASSIGNED', 'EN_ROUTE', 'PICKUP', 'IN_SERVICE', 'BREAK',
  'STANDBY', 'MAINTENANCE', 'BREAKDOWN', 'OFFLINE', 'EMERGENCY'
);

-- Statusuri rezervare (master plan §8)
create type public.booking_status as enum (
  'REQUESTED', 'HELD', 'CONFIRMED', 'DRIVER_ASSIGNED', 'APPROACHING',
  'ARRIVED', 'ON_BOARD', 'COMPLETED', 'CANCELLED', 'NO_SHOW', 'MISSED_PICKUP'
);

-- Evenimente de cursă (master plan §8)
create type public.trip_event_type as enum (
  'TRIP_STARTED', 'PICKUP_APPROACHING', 'ARRIVED_AT_PICKUP', 'PASSENGER_ON_BOARD',
  'PICKUP_AT_RISK', 'PICKUP_MISSED', 'ROUTE_DEVIATION', 'BREAK_STARTED',
  'BREAK_ENDED', 'FUEL_ADDED', 'INCIDENT', 'TRIP_COMPLETED'
);

-- Tipuri noi, introduse de ADR-0002 (nu existau în master plan)
create type public.trip_status as enum ('PLANNED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED');
create type public.member_role as enum ('OWNER', 'ADMIN', 'DISPATCHER', 'DRIVER');
create type public.subscription_status as enum ('TRIAL', 'ACTIVE', 'PAST_DUE', 'READ_ONLY', 'CANCELLED');
create type public.payment_method as enum ('CASH_TO_DRIVER', 'CARD', 'PAYMENT_LINK', 'DEPOSIT_AND_REST');
create type public.stop_kind as enum ('PICKUP', 'DROPOFF');
create type public.stop_status as enum ('PLANNED', 'APPROACHING', 'ARRIVED', 'DONE', 'SKIPPED');
