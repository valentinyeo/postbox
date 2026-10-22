import argparse
from datetime import datetime, timezone
from email import policy
from email.parser import BytesParser
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import struct
import threading
from urllib.parse import parse_qs, unquote, urlsplit
import zlib


KEY = 'fixture-key-not-a-secret'
ACCOUNT = 'personal'
ALPHA = '15550000001@s.whatsapp.net'
BETA = '15550000002@s.whatsapp.net'


def png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = b''.join(b'\x00' + b'\x40\xb0\x90' * 96 for _ in range(64))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 96, 64, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


class State:
    def __init__(self, log):
        self.log = log
        self.lock = threading.Condition()
        self.live = False
        self.archived = False
        self.read = False
        self.media_polls = {}
        self.sends = {}
        self.send_attempts = {}
        self.stamp = datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
        self.image = png()

    def record(self, row):
        with self.lock:
            with self.log.open('a', encoding='utf-8') as stream:
                stream.write(json.dumps(row) + '\n')
                stream.flush()

    def message(self, chat, message_id, text, **extra):
        return dict(MsgID=f'{ACCOUNT}:{message_id}', ChatJID=f'{ACCOUNT}:{chat}', Timestamp=self.stamp,
                    Text=text, DisplayText=text, FromMe=False, SenderName='Fixture Sender',
                    SenderJID=BETA, **extra)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    @property
    def state(self):
        return self.server.state

    def record(self, status, **extra):
        self.state.record(dict(method=self.command, path=self.path, status=status,
                               authorized=self.headers.get('Authorization') == f'Bearer {KEY}',
                               last_event_id=self.headers.get('Last-Event-ID', ''), **extra))

    def respond(self, status, data, content_type='application/json', **extra):
        self.record(status, **extra)
        payload = json.dumps(data).encode() if content_type == 'application/json' else data
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def authorized(self):
        if self.headers.get('Authorization') == f'Bearer {KEY}':
            return True
        self.respond(401, {'error': 'unauthorized'})
        return False

    def do_GET(self):
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        state = self.state
        if url.path == '/v1/accounts':
            self.respond(200, [dict(account='business', state='linked', last_event_at=state.stamp),
                               dict(account=ACCOUNT, jid=BETA, state='linked', last_event_at=state.stamp)])
        elif url.path == '/v1/chats':
            archived = query.get('archived', ['false'])[0] == 'true'
            rows = []
            if archived == state.archived:
                rows.append(dict(jid=f'{ACCOUNT}:{ALPHA}', name='Verification Alpha', kind='direct',
                                 last_message_ts=state.stamp, unread_count=0 if state.read else 2,
                                 archived=state.archived))
            if not archived:
                rows.append(dict(jid=f'{ACCOUNT}:{BETA}', name='Verification Beta', kind='direct',
                                 last_message_ts='2026-01-01T00:00:00Z', unread_count=0, archived=False))
            self.respond(200, rows)
        elif url.path == '/v1/messages':
            chat = query.get('chat', [''])[0].removeprefix(f'{ACCOUNT}:')
            rows = [state.message(chat, 'BASELINE' if chat == ALPHA else 'BASELINE_BETA',
                                  'Fixture history' if chat == ALPHA else 'Fixture Beta history')]
            if chat == ALPHA:
                rows.insert(0, state.message(chat, 'IMAGE', '', MediaType='image', MimeType='image/png',
                                             Filename='fixture.png', LocalPath='server-only-path'))
                if state.live:
                    rows.insert(0, state.message(chat, 'LIVE', 'Fixture live event'))
                for client_id, reply in state.sends.items():
                    if state.send_attempts[client_id] > 1:
                        row = state.message(chat, reply['msg_id'], 'Fixture outgoing')
                        row['FromMe'] = True
                        rows.insert(0, row)
            self.respond(200, rows)
        elif url.path == '/v1/groups':
            self.respond(200, [])
        elif url.path.startswith('/v1/media/'):
            with state.lock:
                poll = state.media_polls.get(url.path, 0) + 1
                state.media_polls[url.path] = poll
            if poll == 1:
                self.respond(202, {'status': 'pending'})
            else:
                self.respond(200, state.image, 'image/png', sha256=hashlib.sha256(state.image).hexdigest())
        elif url.path.startswith('/v1/avatar/'):
            self.respond(404, {'error': 'unavailable'})
        elif url.path == '/v1/events':
            self.events()
        else:
            self.respond(404, {'error': 'unknown path'})

    def events(self):
        self.record(200)
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'close')
        self.end_headers()
        last = int(self.headers.get('Last-Event-ID', '0'))
        if last == 0:
            self.event(1, 'reset', '')
            self.close_connection = True
            return
        while True:
            with self.state.lock:
                if self.state.live and last < 2:
                    self.event(2, 'msg', f'{ACCOUNT}:{ALPHA}')
                    self.close_connection = True
                    return
                self.state.lock.wait(timeout=2)
            self.wfile.write(b': heartbeat\n\n')
            self.wfile.flush()

    def event(self, event_id, kind, chat):
        data = dict(id=event_id, account=ACCOUNT, chat=chat, ts=self.state.stamp, kind=kind)
        self.wfile.write(f'id: {event_id}\ndata: {json.dumps(data)}\n\n'.encode())
        self.wfile.flush()
        self.state.record(dict(method='SSE', path='/v1/events', id=event_id, kind=kind))

    def do_POST(self):
        if not self.authorized():
            return
        payload = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if self.headers.get('Content-Type', '').startswith('multipart/form-data'):
            envelope = BytesParser(policy=policy.default).parsebytes(
                f'Content-Type: {self.headers["Content-Type"]}\r\nMIME-Version: 1.0\r\n\r\n'.encode() + payload)
            body = {part.get_param('name', header='content-disposition'): part.get_content()
                    for part in envelope.iter_parts() if part.get_filename() is None}
        else:
            body = json.loads(payload or '{}')
        state = self.state
        if self.path == '/fixture/live':
            with state.lock:
                state.live = True
                state.lock.notify_all()
            self.respond(200, {'ok': True})
        elif self.path == '/v1/send':
            client_id = body.get('client_id', '')
            if not client_id or body.get('account') != ACCOUNT or body.get('chat') != ALPHA:
                self.respond(400, {'error': 'missing scoped client_id'}, body=body)
                return
            with state.lock:
                duplicate = client_id in state.sends
                if not duplicate:
                    state.sends[client_id] = dict(client_id=client_id, msg_id='SENT', ts=state.stamp, status='sent')
                state.send_attempts[client_id] = state.send_attempts.get(client_id, 0) + 1
                reply = state.sends[client_id]
            if client_id == '53200000000000000000000000000001':
                self.respond(200, reply, body=body, accepted=not duplicate, duplicate=duplicate)
            elif not duplicate:
                self.record(0, body=body, accepted=True, duplicate=False)
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
            else:
                self.respond(200, reply, body=body, accepted=False, duplicate=True)
        elif self.path == '/v1/react':
            self.respond(200, dict(client_id=body['client_id'], msg_id='REACTION', ts=state.stamp, status='sent'), body=body)
        elif self.path == '/v1/mark-read':
            state.read = True
            self.respond(200, {'status': 'ok'}, body=body)
        elif self.path == '/v1/archive':
            state.archived = body['archived']
            self.respond(200, {'status': 'ok'}, body=body)
        else:
            self.respond(404, {'error': 'unknown path'}, body=body)


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Fake bridge runs only on GitHub Actions')
    parser = argparse.ArgumentParser()
    parser.add_argument('--port-file', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    server.state = State(args.log)
    args.port_file.write_text(str(server.server_port), encoding='utf-8')
    server.serve_forever()


if __name__ == '__main__':
    main()
