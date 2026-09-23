"""Adresele (stradă și număr) cu sugestii, cap-coadă, cu browser real și Geoapify fals (fake-geocoder.mjs).
Cere: baza cu fixtures.sql + site-demo.sql + marketplace-demo.sql, PostgREST + proxy.mjs, fake-geocoder.mjs și
aplicația web pornită cu GEOAPIFY_API_KEY=test și GEOAPIFY_BASE_URL=<fake>. Variabile: JWT_SECRET."""
import base64, hashlib, hmac, json, os, time, urllib.request
from datetime import datetime, timedelta, timezone
from playwright.sync_api import sync_playwright

WEB = os.environ.get('WEB_URL', 'http://127.0.0.1:3000')
API = os.environ.get('SUPABASE_URL', 'http://127.0.0.1:54321')
FAKE = os.environ.get('GEOAPIFY_BASE_URL', 'http://127.0.0.1:12112')
SECRET = os.environ['JWT_SECRET'].encode()
CLIENT, DISP = '00000000-0000-0000-0000-00000000cc01', '00000000-0000-0000-0000-00000000a002'
TRIP = '00000000-0000-0000-0000-0000000004a2'   # Timișoara → Wien
steps = []
def ok(m): steps.append(m); print(f'✔ {m}')

def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).rstrip(b'=').decode()
def jwt(c):
    body = f"{b64({'alg': 'HS256', 'typ': 'JWT'})}.{b64({'exp': int(time.time()) + 3600, **c})}"
    return body + '.' + base64.urlsafe_b64encode(hmac.new(SECRET, body.encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
def cookie(sub):
    s = {'access_token': jwt({'sub': sub, 'role': 'authenticated', 'aud': 'authenticated'}), 'token_type': 'bearer',
         'expires_in': 3600, 'expires_at': int(time.time()) + 3600, 'refresh_token': 'test',
         'user': {'id': sub, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}}}
    return 'base64-' + base64.urlsafe_b64encode(json.dumps(s).encode()).rstrip(b'=').decode()
def get(url, headers=None):
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers or {})) as r: return json.loads(r.read())
svc = jwt({'role': 'service_role'}); SH = {'apikey': svc, 'Authorization': f'Bearer {svc}'}
def rest(path): return get(f'{API}/rest/v1/{path}', SH)

departure = rest(f'trips?id=eq.{TRIP}&select=departure_at')[0]['departure_at']
local_date = datetime.fromisoformat(departure).astimezone(timezone(timedelta(hours=3))).strftime('%Y-%m-%d')

# ---------- memoria scurtă: aceeași căutare nu consumă din nou ----------
# punct de referință diferit la fiecare rulare, ca rezultatul să nu fie deja în memoria serverului
lat = 45.0 + (int(time.time()) % 90) / 100
before = get(f'{FAKE}/__requests')['requests']
a = get(f'{WEB}/api/addresses?q=Piata%20Unirii&lat={lat:.2f}&lng=21.23')
b = get(f'{WEB}/api/addresses?q=Piata%20Unirii&lat={lat:.2f}&lng=21.23')
after = get(f'{FAKE}/__requests')['requests']
assert a == b and a['items'][0]['label'].startswith('Piața Unirii 1') and after - before == 1, (a, before, after)
assert a['attribution'].startswith('Powered by Geoapify')
assert all('Paris' not in i['label'] for i in get(f'{WEB}/api/addresses?q=Rue%20de%20Rivoli')['items'])
ok('adrese: aceeași căutare se refolosește (1 cerere la serviciu pentru 2 căutări); doar cele 4 țări')

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM', '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'), args=['--no-sandbox'])

    # ---------- clientul: adresa de preluare din sugestii, cu punct exact ----------
    ctx = browser.new_context(viewport={'width': 390, 'height': 844}, locale='ro-RO', is_mobile=True)
    ctx.add_cookies([{'name': 'sb-127-auth-token', 'value': cookie(CLIENT), 'domain': '127.0.0.1', 'path': '/'}])
    page = ctx.new_page()
    page.goto(f'{WEB}/cauta?from=Timisoara&to=Viena&date={local_date}&pax=1')
    href = page.get_attribute(f'a[href*="/rezerva/{TRIP}"]', 'href')
    assert 'plat=' in href and 'plng=' in href, href
    page.goto(WEB + href)
    page.wait_for_load_state('networkidle')
    if page.locator('input[name=full_name]').count():
        page.fill('input[name=full_name]', 'Client Adrese')
        page.fill('input[name=phone]', '+40711555666')
        page.click('button:has-text("Salvează datele")')
        page.wait_for_selector('input[name=pickup_address]', timeout=15000)
        page.wait_for_load_state('networkidle')
    page.locator('input[name=pickup_address]').press_sequentially('Piata Unirii', delay=40)
    page.wait_for_selector('[role=option]:has-text("Piața Unirii 1")', timeout=10000)
    assert 'Powered by Geoapify' in page.inner_text('.place-suggest')
    page.click('[role=option]:has-text("Piața Unirii 1")')
    assert page.input_value('input[name=pickup_address_lat]') == '45.758'
    page.check('input[value=CASH]')
    page.click('button:has-text("Confirmă rezervarea")')
    page.wait_for_url(lambda u: '/contul-meu' in u, timeout=15000)
    rows = rest(f"bookings?trip_id=eq.{TRIP}&pickup_address=like.Pia*a%20Unirii*&select=id,pickup_address,pickup_location")
    assert rows and rows[-1]['pickup_location'], rows
    ok('clientul își alege adresa din sugestii (lângă localitatea lui); rezervarea are punctul exact de preluare')
    ctx.close()

    # ---------- dispecerul: preluare și destinație din sugestii ----------
    ctx = browser.new_context(viewport={'width': 1440, 'height': 900}, locale='ro-RO')
    ctx.add_cookies([{'name': 'sb-127-auth-token', 'value': cookie(DISP), 'domain': '127.0.0.1', 'path': '/'}])
    page = ctx.new_page()
    page.goto(f'{WEB}/dispecerat/rezervare-noua')
    page.wait_for_load_state('networkidle')
    page.fill('input[name=phone]', '+40722333444')
    page.fill('input[name=name]', 'Pasager Adrese')
    page.select_option('select[name=trip_id]', TRIP)
    page.wait_for_timeout(300)
    page.locator('input[name=pickup_address]').press_sequentially('Piata Victoriei', delay=40)
    page.wait_for_selector('[role=option]:has-text("Piața Victoriei 2")', timeout=10000)
    page.click('[role=option]:has-text("Piața Victoriei 2")')
    page.locator('input[name=dropoff_address]').press_sequentially('Stephansplatz', delay=40)
    page.wait_for_selector('[role=option]:has-text("Stephansplatz 1")', timeout=10000)
    page.click('[role=option]:has-text("Stephansplatz 1")')
    page.click('button:has-text("Salvează rezervarea")')
    page.wait_for_url(lambda u: 'ok=1' in u, timeout=15000)
    rows = rest(f"bookings?trip_id=eq.{TRIP}&pickup_address=like.Pia*a%20Victoriei*&select=pickup_location,dropoff_address,dropoff_location")
    assert rows and rows[-1]['pickup_location'] and rows[-1]['dropoff_location'] and 'Stephansplatz' in rows[-1]['dropoff_address'], rows
    ok('dispecerul alege preluarea și destinația din sugestii; rezervarea are ambele puncte exacte')
    ctx.close()
    browser.close()

print(f'\n{len(steps)} verificări de adrese trecute')
