-- 2100 — Site-ul public al fiecărei firme
--
-- Fiecare firmă are un site: prezentare, rute, flotă, șoferi (doar cu acord), știri și un
-- formular de cerere de rezervare. Adrese: /f/<slug>, <slug>.<domeniu-platformă> sau
-- domeniul propriu al firmei (docs/adr/0007-site-uri-firme.md).
--
-- Vizitatorii nu citesc tabelele. Doar funcțiile get_company_site, get_site_post,
-- resolve_site_domain și submit_booking_request sunt apelabile anonim și întorc strict ce e
-- publicat: site publicat, firmă activă, funcția company_website în plan.
--
-- Coduri de eroare noi: SITE_NOT_FOUND, REQUEST_LIMIT, INVALID_REQUEST.

insert into public.features (key, description) values
  ('company_website', 'Site public al firmei cu știri, flotă, șoferi și cereri de rezervare');
insert into public.plan_features (plan_id, feature_key)
select id, 'company_website' from public.plans where id in ('START', 'PRO', 'PILOT');

create table public.company_sites (
  company_id       uuid primary key references public.companies (id) on delete cascade,
  published        boolean not null default false,
  tagline          text check (length(tagline) <= 160),
  about            text check (length(about) <= 8000),
  phone            text check (length(phone) <= 40),
  whatsapp         text check (length(whatsapp) <= 40),
  email            text check (length(email) <= 120),
  address          text check (length(address) <= 300),
  logo_url         text,
  cover_url        text,
  accent_color     text not null default '#0B4EA2' check (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  custom_domain    text unique check (custom_domain is null or custom_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  seo_description  text check (length(seo_description) <= 300),
  updated_at       timestamptz not null default now()
);

create table public.site_posts (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies (id) on delete cascade,
  slug          text not null check (slug ~ '^[a-z0-9-]{2,80}$'),
  title         text not null check (length(title) between 3 and 160),
  excerpt       text check (length(excerpt) <= 400),
  body          text not null default '' check (length(body) <= 40000),
  cover_url     text,
  published_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (company_id, slug)
);
create index site_posts_published_idx on public.site_posts (company_id, published_at desc) where published_at is not null;

-- Ce apare pe site din flotă, rute și șoferi
alter table public.vehicles
  add column show_on_site boolean not null default false,
  add column public_description text check (length(public_description) <= 500),
  add column photo_url text,
  add column amenities text[] not null default '{}';

alter table public.route_templates
  add column show_on_site boolean not null default false,
  add column public_note text check (length(public_note) <= 200),
  add column price_from_cents int check (price_from_cents is null or price_from_cents >= 0);

-- Profilul public al șoferului cere acordul lui, confirmat de admin (GDPR).
alter table public.drivers
  add column public_profile boolean not null default false,
  add column public_bio text check (length(public_bio) <= 600),
  add column photo_url text,
  add column languages text[] not null default '{}',
  add column driving_since int check (driving_since is null or driving_since between 1950 and 2100),
  add column public_consent_at timestamptz,
  add column public_consent_by uuid,
  add constraint drivers_public_needs_consent check (not public_profile or public_consent_at is not null);

-- Cereri de rezervare de pe site. Dispecerul le preia și le transformă în rezervări.
create table public.booking_requests (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies (id) on delete cascade,
  full_name    text not null check (length(full_name) between 2 and 120),
  phone        text not null check (length(phone) between 6 and 40),
  email        text check (length(email) <= 120),
  from_text    text not null check (length(from_text) between 2 and 160),
  to_text      text not null check (length(to_text) between 2 and 160),
  travel_date  date,
  passengers   int not null default 1 check (passengers between 1 and 60),
  message      text check (length(message) <= 1000),
  locale       text not null default 'ro' check (locale in ('ro', 'de', 'en')),
  status       text not null default 'NEW' check (status in ('NEW', 'CONTACTED', 'CONVERTED', 'REJECTED')),
  handled_by   uuid,
  handled_at   timestamptz,
  created_at   timestamptz not null default now()
);
create index booking_requests_company_idx on public.booking_requests (company_id, status, created_at desc);

-- ---------- RLS (personalul firmei; vizitatorii trec doar prin funcții) ----------

alter table public.company_sites    enable row level security;
alter table public.site_posts       enable row level security;
alter table public.booking_requests enable row level security;

create policy company_sites_select on public.company_sites for select to authenticated
  using (public.is_company_staff(company_id) or public.is_platform_admin());
create policy company_sites_write on public.company_sites for all to authenticated
  using (public.is_company_admin(company_id))
  with check (public.is_company_admin(company_id));

create policy site_posts_select on public.site_posts for select to authenticated
  using (public.is_company_staff(company_id));
create policy site_posts_write on public.site_posts for all to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id));

create policy booking_requests_select on public.booking_requests for select to authenticated
  using (public.is_company_staff(company_id));
create policy booking_requests_update on public.booking_requests for update to authenticated
  using (public.is_company_staff(company_id))
  with check (public.is_company_staff(company_id));

grant select, insert, update, delete on public.company_sites, public.site_posts to authenticated;
grant select, update on public.booking_requests to authenticated;

create trigger company_sites_touch before update on public.company_sites
for each row execute function public.touch_updated_at();
create trigger site_posts_touch before update on public.site_posts
for each row execute function public.touch_updated_at();

-- Acordul șoferului: câmpurile de consimțământ le setează doar funcția de mai jos.
create or replace function public.set_driver_public_profile(
  p_driver_id      uuid,
  p_public         boolean,
  p_consent        boolean,
  p_bio            text default null,
  p_languages      text[] default '{}',
  p_driving_since  int default null,
  p_photo_url      text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.drivers where id = p_driver_id;
  if v_company is null or not public.is_company_admin(v_company) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_public and not p_consent then
    raise exception 'INVALID_REQUEST' using errcode = '22023', detail = 'consent';
  end if;

  update public.drivers
  set public_profile   = p_public,
      public_bio       = nullif(trim(p_bio), ''),
      languages        = coalesce(p_languages, '{}'),
      driving_since    = p_driving_since,
      photo_url        = coalesce(p_photo_url, photo_url),
      public_consent_at = case when p_consent then coalesce(public_consent_at, now()) else null end,
      public_consent_by = case when p_consent then coalesce(public_consent_by, auth.uid()) else null end
  where id = p_driver_id;
end;
$$;

-- ---------- funcții publice ----------

create or replace function public._site_company(p_slug text)
returns uuid
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select c.id
  from public.companies c
  join public.company_sites s on s.company_id = c.id and s.published
  where c.slug = lower(p_slug) and c.status = 'ACTIVE'
    and public.has_feature(c.id, 'company_website');
$$;

create or replace function public.get_company_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := public._site_company(p_slug);
begin
  if v_company is null then
    return null;
  end if;

  return (
    select jsonb_build_object(
      'slug', c.slug,
      'name', c.name,
      'country', c.country,
      'locale', coalesce(cs.default_locale, 'ro'),
      'tagline', s.tagline,
      'about', s.about,
      'phone', s.phone,
      'whatsapp', s.whatsapp,
      'email', s.email,
      'address', s.address,
      'logo_url', s.logo_url,
      'cover_url', s.cover_url,
      'accent_color', s.accent_color,
      'seo_description', s.seo_description,
      'routes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'name', rt.name, 'note', rt.public_note, 'price_from_cents', rt.price_from_cents,
          'points', (select jsonb_agg(p.name order by rtp.seq)
                     from public.route_template_points rtp join public.places p on p.id = rtp.place_id
                     where rtp.template_id = rt.id)
        ) order by rt.name)
        from public.route_templates rt where rt.company_id = c.id and rt.show_on_site), '[]'::jsonb),
      'fleet', coalesce((
        select jsonb_agg(jsonb_build_object(
          'label', v.label, 'seats', v.seats, 'description', v.public_description,
          'photo_url', v.photo_url, 'amenities', v.amenities
        ) order by v.label)
        from public.vehicles v where v.company_id = c.id and v.show_on_site), '[]'::jsonb),
      'drivers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'name', split_part(d.full_name, ' ', 1)
                  || coalesce(' ' || left(nullif(split_part(d.full_name, ' ', 2), ''), 1) || '.', ''),
          'bio', d.public_bio, 'photo_url', d.photo_url, 'languages', d.languages,
          'driving_since', d.driving_since
        ) order by d.full_name)
        from public.drivers d
        where d.company_id = c.id and d.active and d.public_profile and d.public_consent_at is not null), '[]'::jsonb),
      'posts', coalesce((
        select jsonb_agg(x order by x ->> 'published_at' desc) from (
          select jsonb_build_object('slug', sp.slug, 'title', sp.title, 'excerpt', sp.excerpt,
                                    'cover_url', sp.cover_url, 'published_at', sp.published_at) as x
          from public.site_posts sp
          where sp.company_id = c.id and sp.published_at is not null and sp.published_at <= now()
          order by sp.published_at desc limit 30) recent), '[]'::jsonb)
    )
    from public.companies c
    join public.company_sites s on s.company_id = c.id
    left join public.company_settings cs on cs.company_id = c.id
    where c.id = v_company
  );
end;
$$;

create or replace function public.get_site_post(p_slug text, p_post_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := public._site_company(p_slug);
begin
  if v_company is null then
    return null;
  end if;
  return (
    select jsonb_build_object('slug', sp.slug, 'title', sp.title, 'excerpt', sp.excerpt, 'body', sp.body,
                              'cover_url', sp.cover_url, 'published_at', sp.published_at)
    from public.site_posts sp
    where sp.company_id = v_company and sp.slug = lower(p_post_slug)
      and sp.published_at is not null and sp.published_at <= now()
  );
end;
$$;

-- Domeniul propriu al firmei → slug (folosit de middleware-ul aplicației web).
create or replace function public.resolve_site_domain(p_host text)
returns text
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select c.slug
  from public.company_sites s join public.companies c on c.id = s.company_id
  where s.custom_domain = lower(regexp_replace(split_part(p_host, ':', 1), '^www\.', ''))
    and public._site_company(c.slug) is not null;
$$;

create or replace function public.submit_booking_request(
  p_slug         text,
  p_full_name    text,
  p_phone        text,
  p_from         text,
  p_to           text,
  p_travel_date  date,
  p_passengers   int,
  p_message      text default null,
  p_email        text default null,
  p_locale       text default 'ro'
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := public._site_company(p_slug);
  v_phone   text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
begin
  if v_company is null then
    raise exception 'SITE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 or length(v_phone) < 6
     or length(trim(coalesce(p_from, ''))) < 2 or length(trim(coalesce(p_to, ''))) < 2
     or coalesce(p_passengers, 0) not between 1 and 60
     or (p_travel_date is not null and p_travel_date < current_date - 1) then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  -- Limite împotriva abuzului: 5 cereri pe oră de la același telefon, 200 pe zi pe firmă.
  if (select count(*) from public.booking_requests
      where company_id = v_company and phone = v_phone and created_at > now() - interval '1 hour') >= 5
     or (select count(*) from public.booking_requests
         where company_id = v_company and created_at > now() - interval '1 day') >= 200 then
    raise exception 'REQUEST_LIMIT' using errcode = '54000';
  end if;

  insert into public.booking_requests
    (company_id, full_name, phone, email, from_text, to_text, travel_date, passengers, message, locale)
  values (v_company, left(trim(p_full_name), 120), v_phone, nullif(left(trim(coalesce(p_email, '')), 120), ''),
          left(trim(p_from), 160), left(trim(p_to), 160), p_travel_date, p_passengers,
          nullif(left(trim(coalesce(p_message, '')), 1000), ''),
          case when p_locale in ('ro', 'de', 'en') then p_locale else 'ro' end);
  return true;
end;
$$;

-- Numărul de cereri noi, pentru meniul dispecerului.
create or replace function public.count_new_booking_requests(p_company_id uuid)
returns int
language sql stable
security invoker
set search_path = public, pg_temp
as $$
  select count(*)::int from public.booking_requests where company_id = p_company_id and status = 'NEW';
$$;

revoke execute on function public._site_company(text) from public, anon, authenticated;
revoke execute on function public.get_company_site(text), public.get_site_post(text, text),
  public.resolve_site_domain(text),
  public.submit_booking_request(text, text, text, text, text, date, int, text, text, text),
  public.set_driver_public_profile(uuid, boolean, boolean, text, text[], int, text),
  public.count_new_booking_requests(uuid) from public;
grant execute on function public.get_company_site(text), public.get_site_post(text, text),
  public.resolve_site_domain(text),
  public.submit_booking_request(text, text, text, text, text, date, int, text, text, text)
  to anon, authenticated;
grant execute on function public.set_driver_public_profile(uuid, boolean, boolean, text, text[], int, text),
  public.count_new_booking_requests(uuid) to authenticated;
revoke execute on function public.set_driver_public_profile(uuid, boolean, boolean, text, text[], int, text),
  public.count_new_booking_requests(uuid) from anon;

-- ---------- poze (Supabase Storage) ----------
-- Bucket public „site-media”; fiecare firmă scrie doar în folderul ei: <company_id>/...
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage')
     and exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('site-media', 'site-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do nothing;

    execute $p$
      create policy "site-media: firma scrie în folderul ei" on storage.objects for insert to authenticated
      with check (bucket_id = 'site-media' and public.is_company_staff(((storage.foldername(name))[1])::uuid))
    $p$;
    execute $p$
      create policy "site-media: firma modifică în folderul ei" on storage.objects for update to authenticated
      using (bucket_id = 'site-media' and public.is_company_staff(((storage.foldername(name))[1])::uuid))
    $p$;
    execute $p$
      create policy "site-media: firma șterge din folderul ei" on storage.objects for delete to authenticated
      using (bucket_id = 'site-media' and public.is_company_staff(((storage.foldername(name))[1])::uuid))
    $p$;
  end if;
end $$;
