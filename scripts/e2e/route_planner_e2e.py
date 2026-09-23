"""Ordinea preluărilor (Route Planner) și orele pe drum real (Routing API), cap-coadă, cu browser real și
Geoapify fals (fake-geocoder.mjs). Aceleași condiții ca addresses_e2e.py. Variabile: JWT_SECRET."""
import base64, hashlib, hmac, json, os, time, urllib.request
from playwright.sync_api import sync_playwright

WEB = os.environ.get('WEB_URL', 'http://127.0.0.1:3000')
API = os.environ.get('SUPABASE_URL', 'http://127.0.0.1:54321')
FAKE = os.environ.get('GEOAPIFY_BASE_URL', 'http://127.0.0.1:12112')
SECRET = os.environ['JWT_SECRET'].encode()
DISP = '00000000-0000-0000-0000-00000000a002'
TRIP = '00000000-0000-0000-0000-0000000004a2'   # Timișoara → Wien
steps = []
def ok(m): steps.append(m); print(f'✔ {m}')
def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).rstrip(b'=').decode()
def jwt(c):
    body = f"{b64({'alg': 'HS256', 'typ': 'JWT'})}.{b64({'exp': int(time.time()) + 3600, **c})}"
    return body + '.' + base64.urlsafe_b64encode(hmac.new(SECRET, body.encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
def call(method, path, body=None, token=None):
    t = token or jwt({'role': 'service_role'})
    req = urllib.request.Request(f'{API}/rest/v1/{path}', data=json.dumps(body).encode() if body is not None else None, method=method,
                                 headers={'apikey': t, 'Authorization': f'Bearer {t}', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as r: txt = r.read().decode(); return json.loads(txt) if txt else None
counts = lambda: json.loads(urllib.request.urlopen(f'{FAKE}/__requests').read())
disp_token = jwt({'sub': DISP, 'role': 'authenticated', 'aud': 'authenticated'})

# Curățenie: rezervările rămase pe cursa de test (din alte teste și rulări) eliberează locurile
old = call('GET', f"bookings?trip_id=eq.{TRIP}&status=neq.CANCELLED&select=id")
for b in old or []:
    call('PATCH', f"bookings?id=eq.{b['id']}", {'status': 'CANCELLED', 'cancel_reason': 'TEST_CLEANUP'})
    call('PATCH', f"booking_seats?booking_id=eq.{b['id']}&released_at=is.null", {'released_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())})
    call('PATCH', f"trip_stops?booking_id=eq.{b['id']}", {'status': 'SKIPPED'})

# Trei preluări în Timișoara (zona 0), în ordinea proastă: est, vest, centru
stamp = str(int(time.time()))[-5:]
names = {'Est': 21.300, 'Vest': 21.150, 'Centru': 21.220}
for label, lng in names.items():
    call('POST', 'rpc/book_seats', {'p_trip_id': TRIP, 'p_customer_id': '00000000-0000-0000-0000-0000000003a1', 'p_passengers': 1,
         'p_from_seq': 0, 'p_to_seq': 1, 'p_pickup_address': f'Test {label} {stamp}', 'p_pickup_lat': 45.75, 'p_pickup_lng': lng,
         'p_confirm': True}, disp_token)

def order():
    rows = call('GET', f'trip_stops?trip_id=eq.{TRIP}&kind=eq.PICKUP&address=like.Test*{stamp}&select=address,seq,planned_at&order=seq')
    return [r['address'].split()[1] for r in rows], rows

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM', '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'), args=['--no-sandbox'])
    ctx = browser.new_context(viewport={'width': 1440, 'height': 900}, locale='ro-RO')
    sess = {'access_token': disp_token, 'token_type': 'bearer', 'expires_in': 3600, 'expires_at': int(time.time()) + 3600, 'refresh_token': 't',
            'user': {'id': DISP, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}}}
    ctx.add_cookies([{'name': 'sb-127-auth-token', 'value': 'base64-' + base64.urlsafe_b64encode(json.dumps(sess).encode()).rstrip(b'=').decode(),
                      'domain': '127.0.0.1', 'path': '/'}])
    page = ctx.new_page()
    before = counts()
    page.goto(f'{WEB}/dispecerat/curse/{TRIP}/opriri')
    page.click('button:has-text("Optimizează ordinea preluărilor")')
    page.wait_for_url(lambda u: 'optimized=' in u, timeout=20000)
    page.wait_for_selector('.alert-ok', timeout=15000)
    body = page.inner_text('body')
    assert 'optimizată pe drumul real' in body and 'Orele au fost recalculate' in body, body[:600]
    seq, rows = order()
    # Ordinea așteptată: cel mai apropiat vecin (ca serviciul fals) peste TOATE preluările cursei, de la start.
    import math
    stops = [s for s in call('POST', 'rpc/get_trip_stops', {'p_trip_id': TRIP}, disp_token) if s['kind'] == 'PICKUP' and s['lat'] is not None]
    def hav(a, b):
        r = math.radians
        h = math.sin(r(b[0] - a[0]) / 2) ** 2 + math.cos(r(a[0])) * math.cos(r(b[0])) * math.sin(r(b[1] - a[1]) / 2) ** 2
        return 2 * 6371000 * math.asin(math.sqrt(h))
    cur, left, expected = (45.7489, 21.2087), {s['id']: (s['lat'], s['lng']) for s in stops}, []
    while left:
        nxt = min(left, key=lambda i: hav(cur, left[i])); expected.append(nxt); cur = left.pop(nxt)
    actual = [s['id'] for s in sorted(stops, key=lambda s: s['seq'])]
    assert actual == expected, (actual, expected)
    assert seq != ['Est', 'Vest', 'Centru'], seq
    assert all(r['planned_at'] for r in rows)
    after = counts()
    assert after['planner'] - before['planner'] >= 1 and after['routing'] - before['routing'] >= 1, (before, after)
    ok(f'„Optimizează”: preluările din Timișoara reordonate după drum ({" → ".join(seq)} pentru cele 3 de test), orele recalculate pe drum real')

    # recalcularea aceleiași curse: rezultatul pe drum real e refolosit, fără credite noi
    mid = counts()
    page.click('button:has-text("Calculează orele")')
    page.wait_for_url(lambda u: 'times=ok' in u and 'optimized' not in u, timeout=20000)
    page.wait_for_selector('.alert-ok', timeout=15000)
    assert counts()['routing'] == mid['routing'], (mid, counts())
    assert 'aproximative' not in page.inner_text('body')
    ok('„Calculează orele” din nou: ore pe drum real, fără cerere nouă la serviciu (rezultat refolosit)')
    browser.close()

print(f'\n{len(steps)} verificări de rute trecute')
