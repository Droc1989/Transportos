-- Punctul exact de preluare (adresa aleasă din sugestii) pentru rezervarea online a clientului.
--
-- book_marketplace salvează textul adresei; coordonatele adresei alese se adaugă apoi cu
-- set_my_pickup_point. Punctul e acceptat doar dacă e la cel mult 50 km de traseul cursei (ca
-- șoferul să nu fie trimis la o adresă absurdă) și doar înainte de plecare. Fără punct, preluarea
-- rămâne după text și localitate, ca înainte.

create or replace function public.set_my_pickup_point(p_booking_id uuid, p_lat double precision, p_lng double precision)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_booking public.bookings%rowtype;
  v_trip    public.trips%rowtype;
  v_point   geography := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
begin
  if not public.is_booking_client(p_booking_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select * into v_booking from public.bookings where id = p_booking_id;
  select * into v_trip from public.trips where id = v_booking.trip_id;
  if v_trip.status <> 'PLANNED' or v_booking.status not in ('HELD', 'CONFIRMED') then
    raise exception 'TRIP_CLOSED' using errcode = '22023';
  end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180
     or v_trip.route_line is null or not st_dwithin(v_trip.route_line, v_point, 50000) then
    raise exception 'INVALID_REQUEST' using errcode = '22023', detail = 'pickup_far';
  end if;
  update public.bookings set pickup_location = v_point where id = p_booking_id;
end;
$$;

revoke execute on function public.set_my_pickup_point(uuid, double precision, double precision) from public, anon;
grant execute on function public.set_my_pickup_point(uuid, double precision, double precision) to authenticated;
