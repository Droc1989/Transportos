"""Marketplace și plăți, cap-coadă, cu browser real (Playwright) și Stripe fals (fake-stripe.mjs).

Cere: baza cu fixtures.sql + site-demo.sql + marketplace-demo.sql, PostgREST + proxy.mjs,
aplicația web pornită cu STRIPE_SECRET_KEY=sk_test_…, STRIPE_API_BASE=<fake>, STRIPE_WEBHOOK_SECRET,
SUPABASE_SERVICE_ROLE_KEY, și fake-stripe.mjs pornit. Variabile: JWT_SECRET, STRIPE_WEBHOOK_SECRET, CHROMIUM (opțional).
"""
import base64, hashlib, hmac, json, os, time, urllib.request
from datetime import datetime, timedelta, timezone
from playwright.sync_api import sync_playwright

WEB = os.environ.get('WEB_URL', 'http://127.0.0.1:3000')
API = os.environ.get('SUPABASE_URL', 'http://127.0.0.1:54321')
FAKE = os.environ.get('STRIPE_API_BASE', 'http://127.0.0.1:12111')
SECRET = os.environ['JWT_SECRET'].encode()
WHSEC = os.environ['STRIPE_WEBHOOK_SECRET']
CLIENT, OWNER, DRIVER = '00000000-0000-0000-0000-00000000cc01', '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a003'
COMPANY_A, TRIP = '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000004a2'
steps = []

def ok(msg):
    steps.append(msg); print(f'✔ {msg}')

def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).rstrip(b'=').decode()
def jwt(claims):
    body = f"{b64({'alg': 'HS256', 'typ': 'JWT'})}.{b64({'exp': int(time.time()) + 3600, **claims})}"
    return body + '.' + base64.urlsafe_b64encode(hmac.new(SECRET, body.encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
def token(sub): return jwt({'sub': sub, 'role': 'authenticated', 'aud': 'authenticated'})
def cookie(sub):
    s = {'access_token': token(sub), 'token_type': 'bearer', 'expires_in': 3600, 'expires_at': int(time.time()) + 3600,
         'refresh_token': 'test', 'user': {'id': sub, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}}}
    return 'base64-' + base64.urlsafe_b64encode(json.dumps(s).encode()).rstrip(b'=').decode()

def http(method, url, body=None, headers=None):
    data = body.encode() if isinstance(body, str) else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method, headers={'Content-Type': 'application/json', **(headers or {})})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

def rest(sub, path, body=None, method='POST'):
    t = token(sub) if sub != 'service' else jwt({'role': 'service_role'})
    st, txt = http(method, f'{API}/rest/v1/{path}', body, {'apikey': t, 'Authorization': f'Bearer {t}'})
    assert st < 300, f'{path}: {st} {txt}'
    return json.loads(txt) if txt else None

def webhook(event, secret=WHSEC):
    payload = json.dumps(event); ts = int(time.time())
    sig = hmac.new(secret.encode(), f'{ts}.{payload}'.encode(), hashlib.sha256).hexdigest()
    return http('POST', f'{WEB}/api/stripe/webhook', payload, {'Stripe-Signature': f't={ts},v1={sig}'})

# ---------- pornire curată (testul se poate rula de mai multe ori) ----------
http('DELETE', f'{API}/rest/v1/client_profiles?user_id=eq.{CLIENT}', None,
     {'apikey': jwt({'role': 'service_role'}), 'Authorization': f"Bearer {jwt({'role': 'service_role'})}"})
http('DELETE', f'{API}/rest/v1/company_payment_settings?company_id=eq.{COMPANY_A}', None,
     {'apikey': jwt({'role': 'service_role'}), 'Authorization': f"Bearer {jwt({'role': 'service_role'})}"})

# ---------- căutare ----------
places = rest(CLIENT, 'rpc/public_places', {})
tm = next(p for p in places if p['name'] == 'Timișoara'); wien = next(p for p in places if p['name'] == 'Wien')
departure = rest('service', f'trips?id=eq.{TRIP}&select=departure_at', method='GET')[0]['departure_at']
local_date = (datetime.fromisoformat(departure) .astimezone(timezone(timedelta(hours=3)))).strftime('%Y-%m-%d')

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM', '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'), args=['--no-sandbox'])

    anon = browser.new_context()
    page = anon.new_page()
    page.goto(f"{WEB}/cauta?from={tm['id']}&to={wien['id']}&date={local_date}&pax=2")
    body = page.inner_text('main')
    assert 'Firma A' in body and 'Timișoara → Wien' in body and '70' in body, body[:500]
    assert 'Rezervă' in body
    ok('vizitatorul caută Timișoara → Wien și vede firma, prețul și butonul de rezervare')
    anon.close()

    ctx = browser.new_context()
    ctx.add_cookies([{'name': 'sb-127-auth-token', 'value': cookie(CLIENT), 'domain': '127.0.0.1', 'path': '/'}])
    page = ctx.new_page()
    book_url = f'{WEB}/rezerva/{TRIP}?from=0&to=1&pax=2'
    page.goto(book_url)
    page.fill('input[name=full_name]', 'Elena Client')
    page.fill('input[name=phone]', '+40711222333')
    page.click('button:has-text("Salvează datele")')
    page.wait_for_selector('input[name=pickup_address]', timeout=15000)
    body = page.inner_text('main')
    assert 'Totul la șofer' in body and 'Tot acum' not in body, body[:600]
    ok('clientul își completează datele; fără Stripe conectat, firma primește doar plata la șofer')

    # ---------- Stripe conectat prin webhook ----------
    st, _ = webhook({'id': 'evt_bad', 'type': 'account.updated', 'data': {'object': {}}}, secret='whsec_gresit')
    assert st == 400
    st, _ = webhook({'id': 'evt_acc1', 'type': 'account.updated', 'data': {'object': {
        'id': 'acct_firmaA', 'charges_enabled': True, 'metadata': {'company_id': COMPANY_A}}}})
    assert st == 200
    settings = rest(OWNER, f'company_payment_settings?company_id=eq.{COMPANY_A}&select=stripe_account_id,stripe_charges_enabled', method='GET')
    assert settings == [{'stripe_account_id': 'acct_firmaA', 'stripe_charges_enabled': True}], settings
    ok('webhook-ul Stripe (semnat) conectează contul firmei; semnătura greșită e refuzată')

    # ---------- avans online ----------
    page.goto(book_url)
    body = page.inner_text('main')
    assert 'Tot acum' in body and 'Avans acum (28,00' in body, body[:800]
    page.fill('input[name=pickup_address]', 'Timișoara, Piața Unirii 1')
    page.check('input[value=DEPOSIT]')
    page.click('button:has-text("Confirmă rezervarea")')
    page.wait_for_url(lambda u: u.startswith(f'{FAKE}/pay/'))
    session_id = page.url.rsplit('/', 1)[1]
    sessions = json.loads(http('GET', f'{FAKE}/__sessions', None, {'Authorization': 'Bearer sk_test_fake'})[1])
    s = next(x for x in sessions if x['id'] == session_id)
    assert s['account'] == 'acct_firmaA', s
    assert s['form']['line_items[0][price_data][unit_amount]'] == '2800', s['form']
    assert 'application_fee_amount' not in json.dumps(s['form']) and 'transfer_data' not in json.dumps(s['form'])
    ok('avansul de 28 € (20% din 2 × 70 €) se plătește pe contul Stripe al firmei, fără comision al platformei')

    st, _ = webhook({'id': 'evt_pay1', 'type': 'checkout.session.completed', 'account': 'acct_firmaA',
                     'data': {'object': {'id': session_id, 'payment_status': 'paid', 'amount_total': 2800}}})
    assert st == 200
    webhook({'id': 'evt_pay1', 'type': 'checkout.session.completed', 'account': 'acct_firmaA',
             'data': {'object': {'id': session_id, 'payment_status': 'paid', 'amount_total': 2800}}})
    page.goto(f'{WEB}/contul-meu?paid=1')
    body = page.inner_text('main')
    assert 'confirmată' in body and '28,00' in body and '112,00' in body, body[:800]
    ok('plata confirmată de Stripe (și retrimisă) apare o singură dată: 28 € plătit, 112 € la destinație')

    # ---------- numerar ----------
    page.goto(book_url.replace('pax=2', 'pax=1'))
    page.fill('input[name=pickup_address]', 'Timișoara, Str. Test 2')
    page.check('input[value=CASH]')
    page.click('button:has-text("Confirmă rezervarea")')
    page.wait_for_url(lambda u: '/contul-meu' in u)
    assert 'Rezervarea a fost făcută' in page.inner_text('main')
    ok('rezervarea cu plata la șofer merge direct în contul clientului')
    ctx.close()

    # ---------- șoferul vede ce are de încasat ----------
    drv = browser.new_context()
    drv.add_cookies([{'name': 'sb-127-auth-token', 'value': cookie(OWNER), 'domain': '127.0.0.1', 'path': '/'}])
    page = drv.new_page()
    page.goto(f'{WEB}/dispecerat/curse/{TRIP}/pasageri')
    body = page.inner_text('main')
    assert 'Elena Client' in body and '112,00' in body and '70,00' in body, body[:800]
    ok('lista de pasageri arată cât mai e de încasat de la fiecare client')
    drv.close()
    browser.close()

print(f'\n{len(steps)} verificări de marketplace trecute')
