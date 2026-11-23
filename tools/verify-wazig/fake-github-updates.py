from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import hashlib
import json
import os
import ssl
from urllib.parse import urlsplit, parse_qs


RELEASE_FILE = '/valentinyeo/postbox/releases/latest/download/update.json'
NOTES = '- Postbox keeps your conversations and settings'


def release_document(state, payload):
    digest = 'sha256:' + hashlib.sha256(payload).hexdigest()
    release = {
        'tag_name': state['tag'], 'draft': False, 'prerelease': False, 'body': NOTES,
        'assets': [
            {'name': name + state['tag'] + '.zip',
             'browser_download_url': 'https://api.github.com/update.zip',
             'size': len(payload), 'digest': digest}
            for name in ['Messages-', 'Postbox-']
        ],
    }
    return dict(release, history=[{'tag_name': state['tag'], 'body': NOTES}])


class UpdateHandler(BaseHTTPRequestHandler):
    def send(self, status, body, content_type='application/json', headers=None):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        target = urlsplit(self.path)
        root = self.server.root
        state = json.loads((root / 'offer.json').read_text())
        limited = (root / 'rate-limited').exists()
        with (root / 'requests.jsonl').open('a') as log:
            log.write(json.dumps({'path': self.path, 'tag': state['tag'], 'limited': limited}) + '\n')
        if limited and target.path.startswith('/repos/'):
            self.send(403, json.dumps({'message': 'API rate limit exceeded for 127.0.0.1.'}).encode(), headers={'X-RateLimit-Remaining': '0'})
            return
        old = '/repos/valentinyeo/wazig/'
        new = '/repos/valentinyeo/postbox/'
        if target.path.startswith(old):
            self.send_response(301)
            self.send_header('Location', 'https://api.github.com' + self.path.replace(old, new, 1))
            self.end_headers()
            return
        payload = (root / 'update.zip').read_bytes()
        release = release_document(state, payload)
        if target.path == RELEASE_FILE:
            self.send(200, json.dumps(release).encode())
        elif target.path == new + 'releases/latest':
            self.send(200, json.dumps({key: value for key, value in release.items() if key != 'history'}).encode())
        elif target.path == new + 'releases':
            listed = {key: value for key, value in release.items() if key != 'history'}
            self.send(200, json.dumps([listed] if parse_qs(target.query).get('page') == ['1'] else []).encode())
        elif target.path == '/update.zip':
            self.send(200, payload, 'application/zip')
        else:
            self.send_error(404)

    def log_message(self, *_):
        pass


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Update fixture only runs on GitHub Actions')
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', 443), UpdateHandler)
    server.root = args.root
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.root / 'cert.pem', args.root / 'key.pem')
    server.socket = context.wrap_socket(server.socket, server_side=True)
    (args.root / 'ready').write_text('ready')
    server.serve_forever()


if __name__ == '__main__':
    main()
