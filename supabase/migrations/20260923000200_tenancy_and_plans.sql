-- 0200 — Firme (tenanți), membri, planuri și funcții pe plan

create table public.companies (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) > 0),
  slug        text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  country     char(2) not null check (country in ('RO', 'AT', 'DE')),
  status      text not null default 'PENDING_VERIFICATION'
              check (status in ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED')),
  created_at  timestamptz not null default now()
);

create table public.company_settings (
  company_id          uuid primary key references public.companies (id) on delete cascade,
  show_on_public_map  boolean not null default false,
  eta_notify_minutes  int[] not null default '{30,10}',
  default_locale      text not null default 'ro' check (default_locale in ('ro', 'de', 'en')),
  updated_at          timestamptz not null default now()
);

create table public.company_members (
  company_id  uuid not null references public.companies (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  role        public.member_role not null,
  created_at  timestamptz not null default now(),
  primary key (company_id, user_id)
);
create index company_members_user_idx on public.company_members (user_id);

-- Proprietarul platformei (Super Admin). Nu are acces la clienții sau rezervările firmelor.
create table public.platform_admins (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- Planuri și funcții
create table public.plans (
  id                        text primary key,
  name                      text not null,
  price_cents_per_vehicle   int  not null check (price_cents_per_vehicle >= 0),
  min_monthly_price_cents   int  not null default 0 check (min_monthly_price_cents >= 0),
  active                    boolean not null default true
);

create table public.features (
  key          text primary key check (key ~ '^[a-z_]+$'),
  description  text not null
);

create table public.plan_features (
  plan_id      text not null references public.plans (id) on delete cascade,
  feature_key  text not null references public.features (key) on delete cascade,
  primary key (plan_id, feature_key)
);

create table public.company_subscriptions (
  company_id          uuid primary key references public.companies (id) on delete cascade,
  plan_id             text not null references public.plans (id),
  status              public.subscription_status not null default 'TRIAL',
  current_period_end  date,
  updated_at          timestamptz not null default now()
);

-- Pornire/oprire manuală a unei funcții pentru o firmă (ex.: Pro gratuit în pilot)
create table public.company_feature_overrides (
  company_id   uuid not null references public.companies (id) on delete cascade,
  feature_key  text not null references public.features (key) on delete cascade,
  enabled      boolean not null,
  reason       text,
  set_by       uuid references auth.users (id),
  set_at       timestamptz not null default now(),
  primary key (company_id, feature_key)
);

-- Date de referință necesare și în producție
insert into public.features (key, description) values
  ('bookings',                  'Rezervări și clienți'),
  ('seat_segments',             'Locuri pe segmente de traseu'),
  ('dispatch',                  'Dispecerat web și mobil'),
  ('driver_app',                'Aplicația șoferului'),
  ('tracking_link',             'Link de urmărire pentru client'),
  ('passenger_list',            'Lista de pasageri în PDF'),
  ('bookings_export',           'Export rezervări pentru contabilitate'),
  ('eta_traffic_notifications', 'Notificări ETA cu trafic live'),
  ('profit_dashboard',          'Profit pe cursă'),
  ('deviation_reports',         'Rapoarte de abateri de la traseu'),
  ('sms_whatsapp',              'Mesaje SMS și WhatsApp către clienți'),
  ('public_map',                'Apariție pe harta publică și în căutare'),
  ('parcels',                   'Flux colete'),
  ('vehicle_transport',         'Flux mașini pe platformă'),
  ('gps_tracker_integration',   'Integrare tracker GPS existent'),
  ('in_app_navigation',         'Navigație integrată');

insert into public.plans (id, name, price_cents_per_vehicle, min_monthly_price_cents) values
  ('START', 'Start', 2900, 9900),
  ('PRO',   'Pro',   4900, 14900),
  ('PILOT', 'Pilot', 0,    0);

insert into public.plan_features (plan_id, feature_key)
select 'START', key from public.features
where key in ('bookings', 'seat_segments', 'dispatch', 'driver_app',
              'tracking_link', 'passenger_list', 'bookings_export');

insert into public.plan_features (plan_id, feature_key)
select p.id, f.key
from public.plans p
cross join public.features f
where p.id in ('PRO', 'PILOT')
  and f.key in ('bookings', 'seat_segments', 'dispatch', 'driver_app', 'tracking_link',
                'passenger_list', 'bookings_export', 'eta_traffic_notifications',
                'profit_dashboard', 'deviation_reports');
