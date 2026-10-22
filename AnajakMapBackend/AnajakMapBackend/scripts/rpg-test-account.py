"""Create a disposable verified account using the isolated local mail adapter.

Never sends real email. Writes test credentials only to ignored Flutter .local.
"""
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

port = int(os.environ.get('GATEWAY_HTTP_PORT', '8080'))
BASE = f'http://127.0.0.1:{port}/api/v1/'
key = os.environ.get('MAIL_TEST_KEY')
if not key:
    raise SystemExit('MAIL_TEST_KEY is required for the isolated mail adapter')


def call(path, body=None):
    request = urllib.request.Request(BASE + path, data=None if body is None else json.dumps(body).encode(),
                                     headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)['data']


config = call('auth/config')
if config['policyVersion'] != 'automated-test-only':
    raise SystemExit('Refusing to create a fixture outside the isolated test email configuration')
email = 'rpg-test-' + uuid.uuid4().hex + '@example.com'
password = 'Rpg!' + uuid.uuid4().hex
call('auth/register', {'name': 'RPG automated test', 'email': email, 'password': password,
                      'legalConsent': True, 'policyVersion': config['policyVersion']})
for attempt in range(40):
    request = urllib.request.Request('http://127.0.0.1:8095/code?' + urllib.parse.urlencode({'email': email, 'kind': 'VERIFY'}),
                                     headers={'Authorization': 'Bearer ' + key})
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            code = json.load(response)['code']
        break
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise SystemExit('Test mail adapter failed: ' + str(error.code))
        time.sleep(1)
else:
    raise SystemExit('Test verification email did not arrive')
call('auth/verify', {'email': email, 'code': code})
target = Path(__file__).resolve().parents[3] / 'flutter_app/.local/rpg-device.local.json'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps({'RPG_TEST_EMAIL': email, 'RPG_TEST_PASSWORD': password,
                             'API_BASE_URL': f'http://10.0.2.2:{port}/api/v1/'}), encoding='utf-8')
print('Created verified RPG test account. Credentials saved in ignored local test configuration; no real email sent.')
