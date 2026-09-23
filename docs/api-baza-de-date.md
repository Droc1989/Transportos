# API-ul bazei de date

Funcțiile SQL pe care le folosesc aplicațiile, grupate pe cine le apelează. Se apelează prin
Supabase: `supabase.rpc('nume', { p_param: … })`. Erorile vin ca text în `error.message` și se
traduc cu `toDomainError` din `@transportos/shared`.

Regula generală: citirile simple se fac direct din tabele (RLS filtrează), iar tot ce ține de
locuri, stări și poziții trece prin funcțiile de mai jos.

## Dispecer și admin firmă (web)

| Funcție | Ce face |
|---|---|
| `book_seats(trip, customer, passengers, from_seq, to_seq, …, p_confirm, p_idempotency_key)` | Rezervare pe segmente. Fără dublări, idempotentă. Creează automat opririle. |
| `confirm_booking(booking)` / `cancel_booking(booking, reason)` | Confirmare, anulare (eliberează locurile). |
| `free_seats(trip, from_seq, to_seq)` | Locuri libere pe o porțiune. |
| `find_matching_trips(pickup lat/lng, dropoff lat/lng, passengers, window, max_m)` | Cursele care trec pe lângă o adresă, în direcția bună. |
| `save_route_template(company, name, place_ids[])` | Salvează o rută din localitățile din `places`. |
| `create_trip_from_template(template, vehicle, driver, departure, title)` | Cursă nouă dintr-o rută. |
| `cancel_trip(trip)` | Anulează cursa și rezervările; întoarce câți clienți trebuie anunțați. |
| `move_trip_stop(stop, ±1)` / `auto_order_trip_stops(trip)` | Ordinea opririlor. |
| `get_trip_stops(trip)` / `get_trip_route_points(trip)` | Opriri și puncte de traseu cu lat/lng. |
| `set_stop_planned_times(trip, stop_ids[], times[])` | Salvează orele calculate în aplicație. |
| `create_driver_invite(driver)` / `unlink_driver_account(driver)` | Cod de invitație `XXXX-XXXX`; deconectare. |
| `create_tracking_link(booking)` | Token pentru linkul clientului (necesită `tracking_link`). |
| `get_passenger_manifest(trip)` | Lista de pasageri pentru PDF. |
| `export_bookings(company, from, to)` | Export pentru contabilitate (necesită `bookings_export`). |
| `get_dispatch_alerts(company, since)` | SOS deschise + preluări în pericol/ratate. |
| `acknowledge_emergency(event)` / `resolve_emergency(event)` | Dispecerul a văzut alerta / a rezolvat-o. |
| `create_staff_invite(company, role)` | Cod pentru dispecer/admin (proprietar: doar proprietarul sau Super Admin). |
| `change_member_role(company, user, role)` | Schimbă rolul unui membru (OWNER/ADMIN/DISPATCHER). Nimeni nu își schimbă propriul rol; rolul OWNER îl atinge doar un OWNER; rămâne mereu cel puțin un OWNER. |
| `remove_member(company, user)` | Scoate un membru (sau pleci singur). Șoferului i se dezleagă și contul. |

Membrii nu se mai scriu direct în `company_members`. La firmă, personalul poate schimba doar
`name`; la șofer doar `full_name`, `phone`, `active` (contul și acordul trec prin funcții).

## Înscrierea firmei

| Funcție | Ce face |
|---|---|
| `register_company(name, slug, country, registration_no, license_no, phone, accept_terms)` | Firma nouă, în verificare; cel care se înscrie devine proprietar. |
| `declare_vehicle_insurance(vehicle, rca_until, passenger_until, confirm)` | Declarația RCA + asigurare pasageri, cu data și cine a declarat. |
| `get_registration_checklist(company)` | Ce mai lipsește până la trimitere (date, termeni, microbuze complete, microbuze vechi). |
| `submit_company_for_review(company)` | Trimite cererea (doar dacă lista e completă). |
| `update_my_driver_profile(company, bio, languages, driving_since, photo_url, consent)` | Șoferul își completează profilul și își dă acordul. |
| `review_driver_profile(driver, approve, note)` | Firma (admin) aprobă profilul șoferului. |

Pozele microbuzelor sunt în `vehicle_photos` (EXTERIOR, INTERIOR, LUGGAGE, OTHER); condițiile în
`vehicles.features` (listă fixă, `VEHICLE_FEATURES` în `packages/shared`).

## Clienți (marketplace)

| Funcție | Ce face |
|---|---|
| `public_places()` | Cele 38 de orașe de pe coridor, cu coordonate (anonim). |
| `search_places(text, țară?, limită?)` | Localitățile din RO/AT/DE/HU după nume (fără diacritice, denumiri uzuale, început, asemănare) sau după codul poștal („80331”, „D-80331”, „80331 München”), cu județul/regiunea și codul potrivit (anonim). |
| `get_places(id[])` | Localitățile alese, după identificator (anonim, max. 20). |
| `search_marketplace(pickup lat/lng, dropoff lat/lng, passengers, window, max_m)` | Cursele tuturor firmelor active, ordonate după plecare; preț, locuri, microbuz, opțiuni de plată (anonim). |
| `get_marketplace_offer(trip, from_seq, to_seq, passengers)` | Oferta unei curse, pentru pagina de rezervare (anonim). |
| `book_marketplace(trip, from, to, passengers, pickup, notes, 'FULL'/'DEPOSIT'/'CASH', idempotency_key)` | Rezervarea clientului; întoarce plata de făcut și contul Stripe al firmei. |
| `attach_payment_session(payment, session_id)` | Leagă sesiunea Stripe de plată (o singură dată). |
| `my_bookings()` / `client_cancel_booking(booking)` / `client_tracking_link(booking)` | Rezervările clientului, anularea în termen, linkul de urmărire. |
| `record_cash_payment(booking, amount, idempotency_key)` | Restul încasat la destinație (șofer sau dispecer). |

Importul localităților (service_role): `import_places(rânduri)` — `npm run import:places`;
`import_postcodes(rânduri)` — `npm run import:postcodes` (coduri poștale legate de localități).

Webhook-ul Stripe (service_role): `mark_payment_paid(session, amount)`, `mark_payment_expired(session)`,
`mark_payment_refunded(session)`, `set_company_stripe_account(company, account, charges_enabled)`.

## Super Admin

| Funcție | Ce face |
|---|---|
| `admin_pending_companies()` | Firme care așteaptă aprobarea și firme active cu microbuze noi. |
| `review_vehicle(vehicle, approve, note)` | Aprobă sau respinge un microbuz (respingerea cere motiv). |
| `review_company(company, approve, reason)` | Aprobă (cere un microbuz aprobat) sau respinge firma; patronul primește email. |
| `min_vehicle_year()` | Anul minim din `platform_settings` (implicit 2012). |
| `create_company(name, slug, country, plan)` | Firmă nouă, cu setări și abonament. |
| `admin_list_companies()` | Firmele, cu plan, abonament, vehicule și ultima activitate (fără date de clienți). |
| `create_staff_invite(company, 'OWNER')` | Codul pentru patronul firmei. |

Abonamentul și funcțiile pe firmă se modifică direct în `company_subscriptions` și
`company_feature_overrides` (doar Super Admin are drept de scriere).

## Oricine se autentifică

| Funcție | Ce face |
|---|---|
| `accept_invite(code)` | Acceptă orice cod (șofer sau personal); întoarce `{ company, role }`. |

## Aplicația șoferului

| Funcție | Ce face |
|---|---|
| `accept_driver_invite(code)` | Leagă contul de firmă (o singură dată). |
| `get_driver_trips(from, to)` | Cursele șoferului, cu numărul de opriri rămase. |
| `get_trip_stops(trip)` / `get_passenger_manifest(trip)` | Lista opririlor și a pasagerilor (de salvat local pentru lucru fără semnal). |
| `start_trip(trip)` / `complete_trip(trip)` | Pornire / încheiere. |
| `ingest_position(vehicle, lat, lng, recorded_at, speed, heading, trip)` | Poziție GPS. Idempotentă pe `(vehicle, recorded_at)`: la revenirea semnalului se trimite coada locală în ordine. Declanșează detecția de apropiere și de preluare ratată. |
| `mark_stop_arrived(stop)` | „Am ajuns” (anunță clientul). |
| `board_passenger(stop)` / `complete_dropoff(stop)` / `mark_no_show(stop)` | A urcat / a coborât / nu s-a prezentat (eliberează locul). |
| `record_trip_event(trip, type, idempotency_key, payload)` | `BREAK_STARTED`, `BREAK_ENDED`, `FUEL_ADDED`, `INCIDENT`, `ROUTE_DEVIATION`. Cheia (min. 8 caractere) se generează pe telefon. |
| `raise_emergency(vehicle, trip, lat, lng, 'MANUAL'/'AUTO', idempotency_key, speed)` | SOS manual (confirmat imediat) sau detecție automată (posibilă). |
| `dismiss_emergency(event)` / `confirm_emergency(event)` | „SUNT BINE” / numărătoarea a expirat. |

Toate acțiunile șoferului sunt idempotente și nu depind de abonamentul firmei.

## Pagina de urmărire a clientului (anonim)

| Funcție | Ce face |
|---|---|
| `get_tracking_vehicle(token)` | Pozele, condițiile, anul și bagajul microbuzului cursei (fără număr de înmatriculare). |
| `get_tracking(token)` | Singura funcție pentru vizitatori. Întoarce JSON cu firma, cursa, preluarea, câte opriri sunt înainte, iar de la 24 h înainte prenumele șoferului și vehiculul. Poziția exactă apare doar în cursă, când clientul e la bord sau microbuzul e aproape (≤ 3 opriri sau ETA < 90 min). Token greșit sau expirat → `null`. |

Harta publică de pe prima pagină citește direct tabelul `public_live_trips`.

## Site-urile firmelor (anonim)

| Funcție | Ce face |
|---|---|
| `get_company_site(slug)` | Tot conținutul publicat: prezentare, contact, rute, flotă, șoferi cu acord, ultimele 30 de știri. `null` dacă site-ul nu e publicat, firma nu e activă sau nu are `company_website`. |
| `get_site_post(slug, post_slug)` | Un articol publicat (nu ciorne, nu programate). |
| `resolve_site_domain(host)` | Domeniul propriu → slug (folosit de middleware). |
| `submit_booking_request(slug, name, phone, from, to, date, passengers, message, email, locale)` | Cerere de rezervare de pe site (limite: 5/oră/telefon, 200/zi/firmă). |

Dispecerul/adminul editează direct `company_sites` (admin), `site_posts` (tot personalul),
`vehicles.show_on_site…`, `route_templates.show_on_site…`, `booking_requests.status`, iar
profilul public al șoferului prin `set_driver_public_profile(driver, public, consent, bio,
languages, driving_since, photo_url)` (doar admin, cu acord). `count_new_booking_requests(company)`
dă numărul pentru meniu.

## Worker de sistem (`service_role`, ex. Supabase Edge Function + pg_cron)

| Funcție | Când |
|---|---|
| `refresh_public_live_trips()` | la fiecare minut |
| `enqueue_eta_notifications()` | la fiecare minut |
| `claim_notifications(limit)` → trimite → `finish_notification(id, ok, error)` | continuu; reîncercare de până la 5 ori |
| `update_stop_etas(trip, stop_ids[], etas[])` | când recalculează ETA cu trafic (ultimele ~45 min) |
| `worker_tracking_link(booking)` | la fiecare mesaj cu link de urmărire |
| `run_retention()` | zilnic |

Mesajele din coadă (`notification_outbox.template_key`): `BOOKING_CONFIRMED`, `TRIP_CANCELLED`,
`PICKUP_ETA` (`params.minutes`), `DRIVER_ARRIVED`. Canalul e `WHATSAPP` dacă firma are
`sms_whatsapp`, altfel `PUSH`. Textele mesajelor, în limba clientului (`locale`), sunt în worker.
