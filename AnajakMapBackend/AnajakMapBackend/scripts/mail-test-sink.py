"""Isolated test mail adapter. Never use for real users; no external delivery.
Runs only through compose.auth-test.yml. Codes stay outside the application API.
"""
import hmac, json, os
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
from threading import Lock
key = os.environ['MAIL_TEST_KEY']
messages, lock = {}, Lock()
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass  # Never log addresses or codes.
    def reply(self, status, value):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(json.dumps(value).encode())
    def authorized(self):
        return hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + key)
    def do_POST(self):
        if not self.authorized(): return self.reply(403, {})
        if self.path != '/email': return self.reply(404, {})
        length = int(self.headers.get('Content-Length', '0'))
        if not 0 < length < 10000: return self.reply(400, {})
        data = json.loads(self.rfile.read(length))
        with lock: messages[(data['recipient'], data['template'])] = data['code']
        self.reply(200, {})
    def do_GET(self):
        if not self.authorized(): return self.reply(403, {})
        query = parse_qs(urlparse(self.path).query)
        with lock: code = messages.get((query.get('email', [''])[0], query.get('kind', [''])[0]))
        self.reply(200 if code else 404, {'code': code} if code else {})
ThreadingHTTPServer(('0.0.0.0', 8095), Handler).serve_forever()
