"""Căutarea de pe prima pagină → pagina de rezultate, cu browser real (Playwright).
Cere baza cu fixtures.sql + site-demo.sql + marketplace-demo.sql, PostgREST + proxy.mjs și
aplicația web pornită. Variabile: JWT_SECRET, CHROMIUM (opțional), WEB_URL, SUPABASE_URL."""
import base64, hashlib, hmac, json, os, time, urllib.request
from datetime import datetime, timedelta, timezone
from playwright.sync_api import sync_playwright

WEB = os.environ.get('WEB_URL', 'http://127.0.0.1:3000')
API = os.environ.get('SUPABASE_URL', 'http://127.0.0.1:54321')
SECRET = os.environ['JWT_SECRET'].encode()
TRIP = '00000000-0000-0000-0000-0000000004a2'   # Timișoara → Wien, peste 3 zile (site-demo.sql)
steps = []
def ok(m): steps.append(m); print(f'✔ {m}')

def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).rstrip(b'=').decode()
def jwt(c):
    body = f"{b64({'alg': 'HS256', 'typ': 'JWT'})}.{b64({'exp': int(time.time()) + 3600, **c})}"
    return body + '.' + base64.urlsafe_b64encode(hmac.new(SECRET, body.encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
svc = jwt({'role': 'service_role'})
req = urllib.request.Request(f'{API}/rest/v1/trips?id=eq.{TRIP}&select=departure_at', headers={'apikey': svc, 'Authorization': f'Bearer {svc}'})
departure = json.loads(urllib.request.urlopen(req).read())[0]['departure_at']
local_date = datetime.fromisoformat(departure).astimezone(timezone(timedelta(hours=3))).strftime('%Y-%m-%d')

def search(page, frm, to, date=None, pax='2'):
    page.goto(WEB + '/')
    if frm is not None:
        page.fill('#cauta-cursa input[name=from]', frm)
    page.fill('#cauta-cursa input[name=to]', to)
    if date:
        page.click('#cauta-cursa button:has-text("Programat")')
        page.fill('#cauta-cursa input[name=date]', date)
    page.fill('#cauta-cursa input[name=pax]', pax)
    page.click('#cauta-cursa button:has-text("Caută curse")')
    page.wait_for_url(lambda u: '/cauta' in u, timeout=15000)
    page.wait_for_load_state('networkidle')
    return page.inner_text('main')

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM', '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'), args=['--no-sandbox'])

    desk = browser.new_context(viewport={'width': 1440, 'height': 900}, locale='ro-RO')
    page = desk.new_page()
    body = search(page, 'Timisoara', 'Viena', local_date)
    assert 'Firma A' in body and 'Timișoara → Wien' in body and '70' in body, body[:600]
    assert page.locator(f'a[href*="/rezerva/{TRIP}"]').count() == 1
    assert page.eval_on_selector('select[name=from]', 'e => e.options[e.selectedIndex].text') == 'Timișoara'
    assert page.eval_on_selector('select[name=to]', 'e => e.options[e.selectedIndex].text') == 'Wien'
    ok('desktop: „Timisoara” (fără diacritice) → „Viena” găsește cursa spre Wien; orașele apar selectate')

    body = search(page, 'Timișoara', 'Paris', local_date)
    assert '„Paris”' in body and 'Nu am găsit' in body, body[:400]
    ok('oraș necunoscut: mesaj clar cu numele scris („Paris”), nu o pagină goală')

    body = search(page, 'Timișoara', 'Wien')
    assert page.locator(f'a[href*="/rezerva/{TRIP}"]').count() == 0, 'cursa de peste 3 zile nu trebuie să apară la „Acum”'
    assert page.locator('a[href*="/rezerva/00000000-0000-0000-0000-0000000004a1"]').count() == 1, body[:500]
    ok('„Acum”: arată cursa care pleacă în următoarele 24 de ore, nu și pe cea de peste 3 zile')
    desk.close()

    mob = browser.new_context(viewport={'width': 390, 'height': 844}, locale='ro-RO', is_mobile=True, has_touch=True)
    page = mob.new_page()
    body = search(page, 'timișoara', 'Vienna', local_date)
    assert 'Firma A' in body, body[:600]
    overflow = page.evaluate('document.documentElement.scrollWidth - window.innerWidth')
    assert overflow <= 0, f'depășire orizontală: {overflow}px'
    outside = page.evaluate('''() => { const f = document.querySelector('.market-form').getBoundingClientRect();
      return [...document.querySelectorAll('.market-form select, .market-form input, .market-form button')]
        .filter(e => e.type !== 'hidden' && e.getBoundingClientRect().right > f.right + 1).map(e => e.name || e.tagName); }''')
    assert outside == [], f'câmpuri care ies din formular: {outside}'
    ok('telefon 390 px: „Vienna” găsește cursa; fără derulare orizontală, câmpurile rămân în card')
    mob.close()

    gps = browser.new_context(viewport={'width': 390, 'height': 844}, locale='ro-RO', is_mobile=True,
                              geolocation={'latitude': 45.7489, 'longitude': 21.2087}, permissions=['geolocation'])
    page = gps.new_page()
    body = search(page, None, 'Viena', local_date)
    assert 'Firma A' in body and 'lat=' in page.url, (page.url, body[:400])
    assert page.eval_on_selector('select[name=from]', 'e => e.options[e.selectedIndex].text') == 'Locația mea (GPS)'
    assert page.eval_on_selector('input[name=lat]', 'e => e.value').startswith('45.74')
    ok('GPS (în Timișoara): găsește cursa; poziția rămâne în formular pentru o nouă căutare')
    gps.close()
    browser.close()

print(f'\n{len(steps)} verificări ale căutării trecute')
