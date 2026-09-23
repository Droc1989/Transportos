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

def pick(page, field, typed, option_text):
    # tastare reală, după ce pagina e complet încărcată (altfel câmpul nu reacționează încă)
    page.wait_for_load_state('networkidle')
    page.fill(f'#cauta-cursa input[name={field}]', '')
    page.locator(f'#cauta-cursa input[name={field}]').press_sequentially(typed, delay=40)
    page.wait_for_selector(f'#cauta-cursa [role=option]:has-text("{option_text}")', timeout=10000)
    page.click(f'#cauta-cursa [role=option]:has-text("{option_text}")')

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM', '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'), args=['--no-sandbox'])

    desk = browser.new_context(viewport={'width': 1440, 'height': 900}, locale='ro-RO')
    page = desk.new_page()
    body = search(page, 'Timisoara', 'Viena', local_date)
    assert 'Firma A' in body and 'Timișoara → Wien' in body and '70' in body, body[:600]
    assert page.locator(f'a[href*="/rezerva/{TRIP}"]').count() == 1
    assert page.input_value('input[name=from]') == 'Timișoara, Timiș'
    assert page.input_value('input[name=to]') == 'Wien, Wien'
    ok('desktop: „Timisoara” (fără diacritice) → „Viena” găsește cursa spre Wien; orașele apar selectate')

    body = search(page, 'Timișoara', 'Paris', local_date)
    assert '„Paris”' in body and 'Nu am găsit' in body, body[:400]
    ok('oraș necunoscut: mesaj clar cu numele scris („Paris”), nu o pagină goală')

    body = search(page, 'Timișoara', 'Wien')
    assert page.locator(f'a[href*="/rezerva/{TRIP}"]').count() == 0, 'cursa de peste 3 zile nu trebuie să apară la „Acum”'
    assert page.locator('a[href*="/rezerva/00000000-0000-0000-0000-0000000004a1"]').count() == 1, body[:500]
    ok('„Acum”: arată cursa care pleacă în următoarele 24 de ore, nu și pe cea de peste 3 zile')
    # Sugestii: satul Bulgăruș (ales din listă) → „Vien” → Wien (ales din listă)
    page.goto(WEB + '/')
    pick(page, 'from', 'Bulg', 'Bulgăruș')
    pick(page, 'to', 'Vien', 'Wien')
    page.click('#cauta-cursa button:has-text("Programat")')
    page.fill('#cauta-cursa input[name=date]', local_date)
    page.click('#cauta-cursa button:has-text("Caută curse")')
    page.wait_for_url(lambda u: '/cauta' in u, timeout=15000)
    assert page.locator(f'a[href*="/rezerva/{TRIP}"]').count() == 1, page.inner_text('main')[:500]
    assert page.input_value('input[name=from]') == 'Bulgăruș, Timiș'
    ok('sugestii: satul Bulgăruș → Wien, alese din listă, găsesc microbuzul care trece pe lângă sat')

    # Sat cu același nume în mai multe județe: pagina întreabă care
    body = search(page, 'Satu Nou', 'Viena', local_date)
    assert 'Există mai multe localități „Satu Nou”' in body and 'Satu Nou, Arad' in body and 'Satu Nou, Timiș' in body, body[:500]
    page.click('.place-choose a:has-text("Satu Nou, Timiș")')
    page.wait_for_function("document.querySelector('input[name=from]').value === 'Satu Nou, Timiș'", timeout=10000)
    assert page.input_value('input[name=from_id]') != ''
    ok('„Satu Nou” (în două județe): pagina întreabă care, iar alegerea rămâne în formular')
    desk.close()

    # Firma își face ruta din orice localitate, cu sugestii
    disp = browser.new_context(viewport={'width': 1440, 'height': 900}, locale='ro-RO')
    sub = '00000000-0000-0000-0000-00000000a002'
    sess = {'access_token': jwt({'sub': sub, 'role': 'authenticated', 'aud': 'authenticated'}), 'token_type': 'bearer',
            'expires_in': 3600, 'expires_at': int(time.time()) + 3600, 'refresh_token': 'test',
            'user': {'id': sub, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}}}
    disp.add_cookies([{'name': 'sb-127-auth-token', 'value': 'base64-' + base64.urlsafe_b64encode(json.dumps(sess).encode()).rstrip(b'=').decode(),
                       'domain': '127.0.0.1', 'path': '/'}])
    page = disp.new_page()
    page.goto(WEB + '/dispecerat/rute')
    page.wait_for_load_state('networkidle')
    page.fill('input[name=name]', 'Bulgăruș – Wien')
    for typed, option in (('Bulg', 'Bulgăruș'), ('Timisoara', 'Timișoara'), ('Viena', 'Wien')):
        page.fill('input[name=pick_place]', '')
        page.locator('input[name=pick_place]').press_sequentially(typed, delay=40)
        page.wait_for_selector(f'[role=option]:has-text("{option}")', timeout=10000)
        page.click(f'[role=option]:has-text("{option}")')
        page.click('button:has-text("Adaugă")')
    page.click('button:has-text("Salvează ruta")')
    page.wait_for_selector('text=Bulgăruș → Timișoara → Wien', timeout=15000)
    ok('dispecerul face o rută dintr-un sat, cu sugestii (Bulgăruș → Timișoara → Wien)')
    disp.close()

    mob = browser.new_context(viewport={'width': 390, 'height': 844}, locale='ro-RO', is_mobile=True, has_touch=True)
    page = mob.new_page()
    body = search(page, 'timișoara', 'Vienna', local_date)
    assert 'Firma A' in body, body[:600]
    overflow = page.evaluate('document.documentElement.scrollWidth - window.innerWidth')
    assert overflow <= 0, f'depășire orizontală: {overflow}px'
    outside = page.evaluate('''() => { const f = document.querySelector('.market-form').getBoundingClientRect();
      return [...document.querySelectorAll('.market-form input, .market-form button')]
        .filter(e => e.type !== 'hidden' && e.getBoundingClientRect().right > f.right + 1).map(e => e.name || e.tagName); }''')
    assert outside == [], f'câmpuri care ies din formular: {outside}'
    ok('telefon 390 px: „Vienna” găsește cursa; fără derulare orizontală, câmpurile rămân în card')
    mob.close()

    gps = browser.new_context(viewport={'width': 390, 'height': 844}, locale='ro-RO', is_mobile=True,
                              geolocation={'latitude': 45.7489, 'longitude': 21.2087}, permissions=['geolocation'])
    page = gps.new_page()
    body = search(page, None, 'Viena', local_date)
    assert 'Firma A' in body and 'lat=' in page.url, (page.url, body[:400])
    assert page.input_value('input[name=from]') == 'Locația mea (GPS)'
    assert page.eval_on_selector('input[name=lat]', 'e => e.value').startswith('45.74')
    ok('GPS (în Timișoara): găsește cursa; poziția rămâne în formular pentru o nouă căutare')
    gps.close()
    browser.close()

print(f'\n{len(steps)} verificări ale căutării trecute')
