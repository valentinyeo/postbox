import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import struct
import threading
from urllib.parse import parse_qs, urlsplit


TOKEN = 'xoxc-fake-session-token'
COOKIE = 'xoxd-fake-shared-cookie'
TEAM = 'TFAKE001'
CHANNEL = 'CFAKE001'
USER = 'UFAKE001'
BASELINE = '1700000000.000001'
LIVE = '1700000002.000001'
SENT = '1700000001.000001'


def frame(stream, payload):
    data = json.dumps(payload).encode()
    header = bytes([0x81, len(data)]) if len(data) < 126 else b'\x81\x7e' + struct.pack('!H', len(data))
    stream.sendall(header + data)


class State:
    def __init__(self, log=None):
        self.log = log
        self.lock = threading.RLock()
        self.requests = []
        self.sockets = []
        self.sent = []
        self.live = False
        self.acks = 0

    def record(self, row):
        with self.lock:
            self.requests.append(row)
            if self.log:
                with self.log.open('a', encoding='utf-8') as out:
                    out.write(json.dumps(row) + '\n')

    def incoming(self):
        with self.lock:
            self.live = True
            for stream in self.sockets:
                frame(stream, dict(type='message', channel=CHANNEL, ts=LIVE, user='UFAKE002', text='Fake Slack incoming'))
            self.record(dict(method='RTM', path='/rtm', cookie_present=True, authorized=True, event='message'))


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def reply(self, data, status=200):
        raw = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/rtm':
            return self.websocket()
        if path == '/fixture/state':
            with self.server.state.lock:
                return self.reply(dict(sent=len(self.server.state.sent), acks=self.server.state.acks, live=self.server.state.live))
        self.reply(dict(ok=False, error='post_required'), 405)

    def do_POST(self):
        path = urlsplit(self.path).path
        if path == '/fixture/reset':
            with self.server.state.lock:
                self.server.state.sent.clear()
                self.server.state.live = False
                self.server.state.acks = 0
            return self.reply(dict(ok=True))
        if path == '/fixture/live':
            self.server.state.incoming()
            return self.reply(dict(ok=True))
        raw = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        fields = parse_qs(raw.decode(), keep_blank_values=True)
        cookie = self.headers.get('Cookie') == 'd=' + COOKIE
        authorized = (self.headers.get_content_type() == 'application/x-www-form-urlencoded'
                      and fields.get('token') == [TOKEN] and cookie and not self.headers.get('Authorization'))
        self.server.state.record(dict(method='POST', path=path, authorized=authorized, cookie_present=cookie))
        if not authorized:
            return self.reply(dict(ok=False, error='invalid_auth'))
        if urlsplit(self.path).query or any(len(values) != 1 for values in fields.values()):
            return self.reply(dict(ok=False, error='invalid_arguments'))
        if path in ('/api/conversations.list', '/api/users.conversations'):
            return self.reply(dict(ok=True, channels=[dict(id=CHANNEL, name='fake-slack-chat', is_member=True, last_read=BASELINE, unread_count=0)], response_metadata=dict(next_cursor='')))
        if path == '/api/conversations.info':
            return self.reply(dict(ok=True, channel=dict(id=CHANNEL, last_read=BASELINE, unread_count=0)))
        if path == '/api/users.list':
            return self.reply(dict(ok=True, members=[dict(id=USER, name='fake-self'), dict(id='UFAKE002', name='fake-sender')], response_metadata=dict(next_cursor='')))
        if path in ('/api/conversations.history', '/api/conversations.replies'):
            if fields.get('channel') != [CHANNEL]:
                return self.reply(dict(ok=False, error='channel_not_found'))
            messages = [dict(type='message', ts=BASELINE, text='Fake Slack history', user='UFAKE002')]
            with self.server.state.lock:
                messages += list(self.server.state.sent)
                if self.server.state.live:
                    messages.append(dict(type='message', ts=LIVE, text='Fake Slack incoming', user='UFAKE002'))
            return self.reply(dict(ok=True, messages=messages, has_more=False))
        if path == '/api/chat.postMessage':
            if fields.get('channel') != [CHANNEL] or not fields.get('text', [''])[0]:
                return self.reply(dict(ok=False, error='invalid_arguments'))
            with self.server.state.lock:
                self.server.state.sent.append(dict(type='message', ts=SENT, user=USER, text=fields['text'][0], client_msg_id=fields.get('client_msg_id', [''])[0]))
            return self.reply(dict(ok=True, channel=CHANNEL, ts=SENT))
        if path == '/api/conversations.mark':
            return self.reply(dict(ok=True))
        if path == '/api/auth.test':
            return self.reply(dict(ok=True, team_id=TEAM, team='Fake Workspace', user_id=USER))
        if path == '/api/rtm.connect':
            port = self.server.server_port
            return self.reply(dict(ok=True, url=f'ws://127.0.0.1:{port}/rtm', team=dict(id=TEAM), self=dict(id=USER)))
        self.reply(dict(ok=False, error='unknown_method'), 404)

    def websocket(self):
        state = self.server.state
        cookie = self.headers.get('Cookie') == 'd=' + COOKIE
        authorized = cookie and self.headers.get('Upgrade', '').lower() == 'websocket'
        state.record(dict(method='UPGRADE', path='/rtm', authorized=authorized, cookie_present=cookie))
        if not authorized:
            return self.reply(dict(ok=False, error='not_authed'), 401)
        key = self.headers.get('Sec-WebSocket-Key', '')
        accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        self.send_response(101)
        self.send_header('Upgrade', 'websocket')
        self.send_header('Connection', 'Upgrade')
        self.send_header('Sec-WebSocket-Accept', accept)
        self.end_headers()
        with state.lock:
            state.sockets.append(self.connection)
            frame(self.connection, dict(type='hello'))
        try:
            while True:
                header = self.rfile.read(2)
                if len(header) != 2:
                    break
                opcode, size = header[0] & 15, header[1] & 127
                if size == 126:
                    size = struct.unpack('!H', self.rfile.read(2))[0]
                elif size == 127:
                    size = struct.unpack('!Q', self.rfile.read(8))[0]
                mask = self.rfile.read(4) if header[1] & 128 else b''
                data = self.rfile.read(size)
                if opcode == 8:
                    self.connection.sendall(b'\x88\x00')
                    break
                if mask:
                    data = bytes(byte ^ mask[i % 4] for i, byte in enumerate(data))
                if opcode != 1:
                    continue
                value = json.loads(data)
                if 'envelope_id' in value:
                    state.acks += 1
                if value.get('type') == 'ping':
                    state.incoming()
        except (OSError, ValueError):
            pass
        finally:
            with state.lock:
                state.sockets.remove(self.connection)
            self.close_connection = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port-file', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Fake Slack journey runs only on GitHub Actions')
    with ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
        server.daemon_threads = True
        server.state = State(args.log)
        args.port_file.write_text(str(server.server_port), encoding='utf-8')
        server.serve_forever()


if __name__ == '__main__':
    main()
