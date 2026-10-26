from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import hashlib
import json
import os
import ssl
from urllib.parse import urlsplit, parse_qs


class UpdateHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path)
        state = json.loads((self.server.root / 'offer.json').read_text())
        payload = (self.server.root / 'update.zip').read_bytes()
        digest = 'sha256:' + hashlib.sha256(payload).hexdigest()
        row = {'path': self.path, 'tag': state['tag'], 'digest': digest}
        with (self.server.root / 'requests.jsonl').open('a') as log:
            log.write(json.dumps(row) + '\n')
        old = '/repos/valentinyeo/wazig/'
        new = '/repos/valentinyeo/postbox/'
        if path.path.startswith(old):
            self.send_response(301)
            self.send_header('Location', 'https://api.github.com' + self.path.replace(old, new, 1))
            self.end_headers()
            return
        release = {
            'tag_name': state['tag'], 'draft': False, 'prerelease': False,
            'body': '- Postbox keeps your conversations and settings',
            'assets': [
                {'name': name + state['tag'] + '.zip',
                 'browser_download_url': 'https://api.github.com/update.zip',
                 'size': len(payload), 'digest': digest}
                for name in ['Messages-', 'Postbox-']
            ],
        }
        if path.path == new + 'releases/latest':
            data = json.dumps(release).encode()
        elif path.path == new + 'releases':
            data = json.dumps([release] if parse_qs(path.query).get('page') == ['1'] else []).encode()
        elif path.path == '/update.zip':
            data = payload
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'application/zip' if path.path == '/update.zip' else 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

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
