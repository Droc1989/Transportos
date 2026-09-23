-- 0300 — Flotă, șoferi, clienți
-- Fiecare tabel de tenant are company_id și o cheie unică (id, company_id),
-- ca referințele dintre tabele să nu poată amesteca date din firme diferite.

create table public.vehicles (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies (id) on delete cascade,
  label       text not null,                 -- ex. TM-01
  plate       text,
  seats       int  not null check (seats between 1 and 60),
  status      public.vehicle_status not null default 'AVAILABLE',
  is_standby  boolean not null default false, -- vehicul de rezervă (nefacturat cât stă în standby)
  created_at  timestamptz not null default now(),
  unique (company_id, label),
  unique (id, company_id)
);

create table public.drivers (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies (id) on delete cascade,
  user_id     uuid references auth.users (id) on delete set null,
  full_name   text not null,
  phone       text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (company_id, user_id),
  unique (id, company_id)
);
create index drivers_user_idx on public.drivers (user_id);

-- Clienții aparțin firmei (firma e operatorul de date, platforma doar le prelucrează).
create table public.customers (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies (id) on delete cascade,
  full_name   text not null,
  phone       text not null,
  locale      text not null default 'ro' check (locale in ('ro', 'de', 'en')),
  notes       text,
  created_at  timestamptz not null default now(),
  unique (company_id, phone),
  unique (id, company_id)
);
