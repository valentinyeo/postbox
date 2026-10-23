import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import struct
from http.server import ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlencode, urlsplit
import zlib


spec = importlib.util.spec_from_file_location('bridge_fixture', Path(__file__).with_name('fake-wa-bridge.py'))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
ALPHA = 'fixture-alpha'
BETA = 'fixture-beta'


WORKSPACE_CHATS = [
    ('slack:fixture-amber:channel-alpha', 'Verification Amber', 'slack'),
    ('slack:fixture-cobalt:channel-beta', 'Verification Cobalt', 'slack'),
    ('slack:fixture-empty:channel-gamma', 'Verification Empty', 'slack'),
    ('whatsapp:fixture:contact-delta', 'Verification Delta', 'whatsapp'),
]
WORKSPACE_COLOURS = {'fixture-amber': (240, 160, 32), 'fixture-cobalt': (48, 112, 240)}


def workspace_png(team):
    colour = WORKSPACE_COLOURS[team]
    letter = ['01110', '11011', '11011', '11111', '11011', '11011', '11011'] if team == 'fixture-amber' else [
        '01111', '11000', '11000', '11000', '11000', '11000', '01111']
    rows = []
    for y in range(64):
        row = bytearray(b'\x00')
        for x in range(64):
            gx, gy = (x - 22) // 4, (y - 18) // 4
            ink = 0 <= gx < 5 and 0 <= gy < 7 and letter[gy][gx] == '1'
            row.extend((255, 255, 255) if ink else colour)
        rows.append(row)

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 64, 64, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND', b'')


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
        if url.path.startswith('/v1/wazig/workspace-icon/'):
            if not self.authorized():
                return
            self.workspace_icon(url.path)
            return
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

    def workspace_icon(self, path):
        team = unquote(path.removeprefix('/v1/wazig/workspace-icon/'))
        if team in WORKSPACE_COLOURS:
            image = workspace_png(team)
            self.respond(200, image, 'image/png', sha256=hashlib.sha256(image).hexdigest())
        else:
            self.respond(404, {'error': 'workspace icon unavailable'})

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


class SlackSortHandler(Handler):
    def respond(self, status, data, content_type='application/json', **extra):
        bridge.Handler.respond(self, status, data, content_type, **extra)

    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            rows = [dict(jid=chat, name=name, provider='slack', kind='direct',
                         last_message_ts=self.state.sort_times[chat], unread_count=0, archived=False)
                    for chat, name in [('fixture-alpha', 'Verification Alpha'),
                                       ('fixture-unknown', 'Verification Aardvark'),
                                       ('fixture-gamma', 'Verification Gamma'),
                                       ('fixture-beta', 'Verification Beta')]]
            self.respond(200, rows if query.get('archived', ['false'])[0] == 'false' else [])
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            stamp = self.state.sort_initial.get(chat, '')
            rows = [] if not stamp else [dict(MsgID='SORT-' + chat, ChatJID=chat, Timestamp=stamp,
                                              Text='Synthetic last message', FromMe=chat == 'fixture-gamma',
                                              SenderName='Fixture Sender')]
            if chat == ALPHA and self.state.live:
                rows.insert(0, dict(MsgID='SORT-LIVE', ChatJID=chat, Timestamp=self.state.sort_times[chat],
                                    Text='Synthetic Slack incoming', FromMe=False, SenderName='Fixture Sender'))
            if chat == 'fixture-gamma' and self.state.sort_times[chat] != stamp:
                rows.insert(0, dict(MsgID='SORT-SENT', ChatJID=chat, Timestamp=self.state.sort_times[chat],
                                    Text='Synthetic Slack outgoing', FromMe=True, SenderName='Fixture Sender'))
            self.respond(200, rows)
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path.startswith('/v1/wazig/avatar/'):
            self.respond(404, {'error': 'unavailable'})
        else:
            self.respond(404, {'error': 'unknown sort path'})

    def do_POST(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        if self.path == '/fixture/live':
            with self.state.lock:
                self.state.sort_times[ALPHA] = self.state.stamp
                self.state.live = True
                self.state.lock.notify_all()
            self.respond(200, {'ok': True})
        elif self.path == '/v1/wazig/mark-read':
            self.respond(200, {'status': 'ok'}, body=body)
        elif self.path == '/v1/wazig/send' and body.get('chat') == 'fixture-gamma':
            stamp = (datetime.fromisoformat(self.state.stamp) + timedelta(seconds=1)).isoformat().replace('+00:00', 'Z')
            self.state.sort_times['fixture-gamma'] = stamp
            self.respond(200, dict(client_id=body['client_id'], msg_id='SORT-SENT', ts=stamp, status='sent'), body=body)
        else:
            self.respond(400, {'error': 'invalid sort request'}, body=body)


VIEW_ACCOUNTS = [
    ('slack', 'T0ABC123', ''),
    ('whatsapp', 'personal', ''),
    ('slack', 'T0DEF456', ''),
    ('whatsapp', 'business', ''),
]


def view_account(row):
    parts = row['jid'].split(':')
    return parts[1] if row['provider'] == 'slack' else parts[0]


def view_rows():
    rows = []
    for index, (provider, account, name) in enumerate(VIEW_ACCOUNTS):
        for contact in range(2):
            stamp = datetime(2026, 1, 1, 0, index * 2 + contact, tzinfo=timezone.utc)
            jid = f'slack:{account}:C{contact:010d}' if provider == 'slack' else f'{account}:{contact:010d}@s.whatsapp.net'
            rows.append(dict(jid=jid, provider=provider, name='Verification Shared' if contact == 0 else 'Verification Other',
                             kind='direct', last_message_ts=stamp.isoformat().replace('+00:00', 'Z'),
                             unread_count=0, archived=False))
    return rows


class ViewsHandler(Handler):
    def respond(self, status, data, content_type='application/json', **extra):
        bridge.Handler.respond(self, status, data, content_type, **extra)

    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            with self.state.lock:
                rows = json.loads(json.dumps(self.state.view_rows))
            self.respond(200, [] if query.get('archived') == ['true'] else rows)
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            row = next((row for row in self.state.view_rows if row['jid'] == chat), None)
            if row is None:
                self.respond(404, {'error': 'unknown fixture chat'})
                return
            with self.state.lock:
                rows = [dict(MsgID=f'baseline-{chat}', ChatJID=chat, Timestamp=row['last_message_ts'],
                             Text=f'History {view_account(row)}', FromMe=False, SenderName='Verification Shared')]
                rows.extend(dict(MsgID=reply['msg_id'], ChatJID=chat, Timestamp=reply['ts'],
                                 Text=reply['text'], FromMe=True, SenderName='Verification Sender')
                            for reply in self.state.sends.values() if reply['chat'] == chat)
            self.respond(200, rows)
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path.startswith('/v1/wazig/avatar/'):
            self.respond(404, {'error': 'unavailable'})
        else:
            self.respond(404, {'error': 'unknown fixture route'})

    def do_POST(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        row = next((row for row in self.state.view_rows if row['jid'] == body.get('chat')), None)
        if row is None:
            self.respond(400, {'error': 'unknown fixture chat'}, body=body)
            return
        scope = dict(source_provider=row['provider'], source_account=view_account(row))
        if self.path == '/v1/wazig/send':
            if set(body) != {'chat', 'text', 'reply_to', 'client_id'} or not body['client_id']:
                self.respond(400, {'error': 'invalid send'}, body=body)
                return
            with self.state.lock:
                duplicate = body['client_id'] in self.state.sends
                if not duplicate:
                    self.state.sends[body['client_id']] = dict(client_id=body['client_id'], msg_id='views-sent',
                        ts=self.state.stamp, status='sent', chat=body['chat'], text=body['text'])
                    row['last_message_ts'] = self.state.stamp
                reply = dict(self.state.sends[body['client_id']])
            self.respond(200, reply, body=body, accepted=not duplicate, duplicate=duplicate, **scope)
        elif self.path == '/v1/wazig/mark-read' and set(body) == {'chat', 'message_id'}:
            self.respond(200, {'status': 'ok'}, body=body, **scope)
        else:
            self.respond(400, {'error': 'unexpected fixture write'}, body=body, **scope)


class WorkspaceIconsHandler(Handler):
    def respond(self, status, data, content_type='application/json', **extra):
        bridge.Handler.respond(self, status, data, content_type, **extra)

    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            rows = [dict(jid=chat, name=name, provider=provider, kind='direct',
                         last_message_ts=self.state.stamp, unread_count=0, archived=False)
                    for chat, name, provider in WORKSPACE_CHATS]
            self.respond(200, rows if query.get('archived', ['false'])[0] == 'false' else [])
        elif url.path in ('/v1/wazig/messages', '/v1/wazig/groups'):
            self.respond(200, [])
        elif url.path.startswith('/v1/wazig/workspace-icon/'):
            self.workspace_icon(url.path)
        elif url.path.startswith('/v1/wazig/avatar/'):
            self.respond(404, {'error': 'unavailable'})
        elif url.path == '/v1/wazig/events':
            self.events()
        else:
            self.respond(404, {'error': 'unknown workspace fixture path'})

    def do_POST(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        if self.path == '/v1/wazig/mark-read' and body.get('chat') in [row[0] for row in WORKSPACE_CHATS]:
            self.respond(200, {'status': 'ok'}, body=body)
        else:
            self.respond(400, {'error': 'unexpected workspace fixture write'}, body=body)


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Fake hub runs only on GitHub Actions')
    parser = argparse.ArgumentParser()
    parser.add_argument('--port-file', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--slack-sort', action='store_true')
    modes.add_argument('--views', action='store_true')
    modes.add_argument('--workspace-icons', action='store_true')
    args = parser.parse_args()
    loopback = socket.inet_ntoa(struct.pack('!I', socket.INADDR_LOOPBACK))
    handler = ViewsHandler if args.views else WorkspaceIconsHandler if args.workspace_icons else SlackSortHandler if args.slack_sort else Handler
    server = ThreadingHTTPServer((loopback, 0), handler)
    server.daemon_threads = True
    server.state = bridge.State(args.log)
    server.state.view_rows = view_rows()
    if args.slack_sort:
        stamp = datetime.fromisoformat(server.state.stamp)
        server.state.sort_times = {
            ALPHA: (stamp - timedelta(hours=3)).isoformat().replace('+00:00', 'Z'),
            BETA: (stamp - timedelta(hours=1)).isoformat().replace('+00:00', 'Z'),
            'fixture-gamma': (stamp - timedelta(hours=2)).isoformat().replace('+00:00', 'Z'),
            'fixture-unknown': '',
        }
        server.state.sort_initial = dict(server.state.sort_times)
    args.port_file.write_text(str(server.server_port), encoding='utf-8')
    server.serve_forever()


if __name__ == '__main__':
    main()
