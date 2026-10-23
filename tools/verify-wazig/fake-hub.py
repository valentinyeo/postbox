import argparse
from datetime import datetime, timedelta
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import struct
from http.server import ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlsplit


spec = importlib.util.spec_from_file_location('bridge_fixture', Path(__file__).with_name('fake-wa-bridge.py'))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
ALPHA = 'fixture-alpha'
BETA = 'fixture-beta'


class Handler(bridge.Handler):
    def record(self, status, **extra):
        if 'body' in extra and hasattr(self, 'wire_body'):
            extra['body'] = self.wire_body
        super().record(status, wire_path=self.wire_path, **extra)

    def respond(self, status, data, content_type='application/json', **extra):
        if content_type == 'application/json' and isinstance(data, list):
            data = json.loads(json.dumps(data).replace(bridge.ACCOUNT + ':', '').replace(bridge.ALPHA, ALPHA).replace(bridge.BETA, BETA))
            for row in data:
                if 'jid' in row:
                    row['provider'] = 'slack' if row['jid'] == ALPHA else 'whatsapp'
                    if row['jid'] == BETA:
                        stamp = datetime.fromisoformat(row['last_message_ts']) - timedelta(seconds=1)
                        row['last_message_ts'] = stamp.isoformat().replace('+00:00', 'Z')
        super().respond(status, data, content_type, **extra)

    def do_GET(self):
        self.wire_path = self.path
        url = urlsplit(self.path)
        if not url.path.startswith('/v1/wazig/'):
            self.respond(400, {'error': 'expected unified API'})
            return
        route = url.path.replace('/v1/wazig/', '/v1/', 1)
        query = parse_qs(url.query, keep_blank_values=True)
        if route in ('/v1/chats', '/v1/messages'):
            if 'account' in query:
                self.respond(400, {'error': 'source account must stay on hub'})
                return
            query['account'] = [bridge.ACCOUNT]
            if 'chat' in query:
                query['chat'] = [{ALPHA: bridge.ALPHA, BETA: bridge.BETA}.get(query['chat'][0], '')]
        if route.startswith('/v1/media/'):
            route = route.replace('/v1/media/', '/v1/media/' + bridge.ACCOUNT + '/', 1)
        if route.startswith('/v1/avatar/'):
            route = route.replace('/v1/avatar/', '/v1/avatar/' + bridge.ACCOUNT + '/', 1)
        route = route.replace(ALPHA, bridge.ALPHA).replace(BETA, bridge.BETA)
        self.path = route + ('?' + urlencode(query, doseq=True) if query else '')
        super().do_GET()

    def event(self, event_id, kind, chat):
        handle = chat.removeprefix(bridge.ACCOUNT + ':').replace(bridge.ALPHA, ALPHA).replace(bridge.BETA, BETA)
        data = dict(id=event_id, chat=handle, kind=kind)
        self.wfile.write(f'id: {event_id}\ndata: {json.dumps(data)}\n\n'.encode())
        self.wfile.flush()
        self.state.record(dict(method='SSE', path='/v1/events', wire_path=self.wire_path, id=event_id, kind=kind))

    def do_POST(self):
        self.wire_path = self.path
        if self.path == '/fixture/live':
            super().do_POST()
            return
        if not self.path.startswith('/v1/wazig/'):
            self.respond(400, {'error': 'expected unified API'})
            return
        if not self.authorized():
            return
        data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        body = json.loads(data)
        fields = {
            '/v1/wazig/send': {'chat', 'text', 'reply_to', 'client_id'},
            '/v1/wazig/mark-read': {'chat', 'message_id'},
            '/v1/wazig/archive': {'chat', 'archived'},
            '/v1/wazig/react': {'chat', 'msg', 'emoji', 'client_id'},
        }
        if set(body) != fields.get(self.path) or body.get('chat') not in (ALPHA, BETA):
            self.respond(400, {'error': 'invalid unified payload'}, body=body)
            return
        self.wire_body = dict(body)
        body['chat'] = {ALPHA: bridge.ALPHA, BETA: bridge.BETA}[body['chat']]
        body['account'] = bridge.ACCOUNT
        encoded = json.dumps(body).encode()
        self.rfile = io.BytesIO(encoded)
        self.headers.replace_header('Content-Length', str(len(encoded)))
        self.path = self.path.replace('/v1/wazig/', '/v1/', 1)
        super().do_POST()


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Fake hub runs only on GitHub Actions')
    parser = argparse.ArgumentParser()
    parser.add_argument('--port-file', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    loopback = socket.inet_ntoa(struct.pack('!I', socket.INADDR_LOOPBACK))
    server = ThreadingHTTPServer((loopback, 0), Handler)
    server.daemon_threads = True
    server.state = bridge.State(args.log)
    args.port_file.write_text(str(server.server_port), encoding='utf-8')
    server.serve_forever()


if __name__ == '__main__':
    main()
