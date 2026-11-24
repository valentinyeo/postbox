import base64
import hashlib
import json
import struct
import threading
import os
import re
from urllib.parse import parse_qs, urlsplit


DICTATION_ACCOUNT = 'fixture-workspace'
DICTATION_CHATS = {
    'slack:fixture-workspace:channel-alpha': 'Verification Alpha',
    'slack:fixture-workspace:channel-beta': 'Verification Beta',
}


class DictationHandler(Handler):
    def respond(self, status, data, content_type='application/json', **extra):
        bridge.Handler.respond(self, status, data, content_type, **extra)

    def intents(self):
        if not hasattr(self.state, 'dictation_intents'):
            path = self.state.log.with_name('dictation-accepted.jsonl')
            records = {}
            if path.exists():
                with path.open(encoding='utf-8') as stream:
                    for line in stream:
                        record = json.loads(line)
                        client_id = record['client_id']
                        if client_id in records:
                            raise ValueError('duplicate durable fixture identity')
                        records[client_id] = record
            self.state.dictation_intents = records
        return self.state.dictation_intents

    def do_GET(self):
        self.wire_path = self.path
        url = urlsplit(self.path)
        if url.path == '/v1/listen':
            self.live_dictation(parse_qs(url.query))
            return
        if not self.authorized():
            return
        if url.path == '/dictation-live/advance':
            with self.state.lock:
                self.state.live_advance.set()
            self.respond(200, {'status': 'ok'})
            return
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            rows = [] if query.get('archived') == ['true'] else [
                dict(jid=chat, name=name, provider='slack', account=DICTATION_ACCOUNT,
                     team_name='Verification Workspace', kind='direct',
                     last_message_ts=('2026-01-02T00:00:00Z' if chat.endswith('alpha') else '2026-01-01T00:00:00Z'),
                     unread_count=0, archived=False)
                for chat, name in DICTATION_CHATS.items()
            ]
            self.respond(200, rows)
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            if chat not in DICTATION_CHATS:
                self.respond(404, {'error': 'unknown fixture chat'})
                return
            with self.state.lock:
                records = list(self.intents().values())
            rows = [dict(MsgID='DICTATION-HISTORY', ChatJID=chat, Timestamp=self.state.stamp,
                         Text='Synthetic history', FromMe=False, SenderName='Fixture Sender',
                         SenderJID='fixture-sender')]
            rows.extend(dict(MsgID=record['msg_id'], ChatJID=chat, Timestamp=record['ts'],
                             Text=record['text'], FromMe=True, SenderName='You',
                             quoted_msg_id=record['reply_to'])
                        for record in records if record['chat'] == chat)
            self.respond(200, rows)
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        else:
            self.respond(404, {'error': 'unavailable'})

    def do_POST(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or b'{}')
        except (ValueError, UnicodeDecodeError):
            self.respond(400, {'error': 'invalid fixture JSON'})
            return
        if not isinstance(body, dict) or body.get('chat') not in DICTATION_CHATS:
            self.respond(400, {'error': 'unknown fixture chat'}, body=body)
            return
        if self.path == '/v1/wazig/mark-read' and set(body) == {'chat', 'message_id'}:
            self.respond(200, {'status': 'ok'}, body=body)
            return
        if self.path != '/v1/wazig/send' or set(body) != {'chat', 'text', 'reply_to', 'client_id'}:
            self.respond(400, {'error': 'invalid fixture write'}, body=body)
            return
        client_id = body['client_id']
        if (not isinstance(client_id, str) or not re.fullmatch(r'[0-9a-f]{32}', client_id)
                or not isinstance(body['text'], str) or not body['text']
                or not isinstance(body['reply_to'], str)):
            self.respond(400, {'error': 'invalid fixture send'}, body=body)
            return
        self.capture_identity_ingress()
        self.capture_identity_snapshot(body)
        with self.state.lock:
            intents = self.intents()
            previous = intents.get(client_id)
            expected = dict(provider='slack', account=DICTATION_ACCOUNT, chat=body['chat'],
                            text=body['text'], reply_to=body['reply_to'], client_id=client_id)
            if previous is not None and any(previous[key] != value for key, value in expected.items()):
                self.respond(409, {'error': 'fixture identity mismatch'}, body=body,
                             accepted=False, duplicate=True)
                return
            duplicate = previous is not None
            if not duplicate:
                previous = dict(expected, msg_id='dictation-' + client_id, ts=self.state.stamp, status='sent')
                path = self.state.log.with_name('dictation-accepted.jsonl')
                with path.open('a', encoding='utf-8') as stream:
                    stream.write(json.dumps(previous, ensure_ascii=True) + '\n')
                    stream.flush()
                    os.fsync(stream.fileno())
                intents[client_id] = previous
            reply = {key: previous[key] for key in ('client_id', 'msg_id', 'ts', 'status')}
            self.respond(200, reply, body=body, source_provider='slack', source_account=DICTATION_ACCOUNT,
                         accepted=not duplicate, duplicate=duplicate)

    def live_frame(self, opcode, data, final=True):
        header = bytes([(0x80 if final else 0) | opcode])
        length = len(data)
        header += bytes([length]) if length < 126 else b'\x7e' + struct.pack('!H', length)
        self.wfile.write(header + data)
        self.wfile.flush()

    def live_read(self, count):
        data = self.rfile.read(count)
        if len(data) != count:
            raise ConnectionError('truncated fixture WebSocket')
        return data

    def live_result(self, transcript, final, language, fragmented=False):
        data = json.dumps(dict(type='Results', start=0, duration=1, is_final=final,
                               channel=dict(alternatives=[dict(transcript=transcript, languages=[language])]))).encode()
        if fragmented:
            middle = len(data) // 2
            self.live_frame(1, data[:middle], final=False)
            self.live_frame(0, data[middle:])
        else:
            self.live_frame(1, data)

    def live_dictation(self, query):
        expected = dict(model=['nova-3'], smart_format=['true'], interim_results=['true'],
                        encoding=['linear16'], sample_rate=['16000'], channels=['1'], tag=['wazig'])
        language = query.get('language')
        if language == ['multi']:
            expected.update(language=['multi'], language_hint=['en', 'de'])
        elif language in (['en'], ['de']):
            expected['language'] = language
        if (query != expected or self.headers.get('Upgrade', '').lower() != 'websocket'
                or self.headers.get('Authorization', '').strip() != 'Token'):
            self.respond(400, {'error': 'invalid live dictation request'})
            return
        key = self.headers.get('Sec-WebSocket-Key', '')
        accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        self.send_response(101)
        self.send_header('Upgrade', 'websocket')
        self.send_header('Connection', 'Upgrade')
        self.send_header('Sec-WebSocket-Accept', accept)
        self.end_headers()
        self.wfile.flush()
        self.connection.settimeout(30)
        advance = threading.Event()
        with self.state.lock:
            self.state.live_advance = advance
        selected = language[0]
        detected = 'de' if selected == 'de' else 'en'
        first, revised, final = ('Grü', 'Grüße aus', 'Grüße aus Berlin.') if detected == 'de' else ('hello', 'hello world', 'Hello world.')
        stage = 0
        audio_bytes = 0
        self.state.record(dict(kind='dictation-live', stage='open', language=selected, query=query))
        self.close_connection = True
        try:
            while True:
                flags, size = self.live_read(2)
                opcode = flags & 15
                if not flags & 128 or not size & 128:
                    raise ValueError('fixture requires complete masked client frames')
                size &= 127
                if size == 126:
                    size = struct.unpack('!H', self.live_read(2))[0]
                elif size == 127:
                    size = struct.unpack('!Q', self.live_read(8))[0]
                if size > 1024 * 1024:
                    raise ValueError('oversized fixture frame')
                mask = self.live_read(4)
                data = bytes(value ^ mask[index % 4] for index, value in enumerate(self.live_read(size)))
                if opcode == 8:
                    return
                if opcode == 9:
                    self.live_frame(10, data)
                    continue
                if opcode == 2:
                    if not data or len(data) % 2:
                        raise ValueError('invalid PCM frame')
                    audio_bytes += len(data)
                    if stage == 0:
                        self.live_result(first, False, detected, fragmented=True)
                        stage = 1
                        self.state.record(dict(kind='dictation-live', stage='interim', language=selected, audio_bytes=audio_bytes))
                    elif stage == 1 and advance.is_set():
                        self.live_result(revised, False, detected)
                        stage = 2
                        self.state.record(dict(kind='dictation-live', stage='revised', language=selected, audio_bytes=audio_bytes))
                elif opcode == 1 and json.loads(data) == {'type': 'CloseStream'}:
                    if stage != 2:
                        raise ValueError('stopped before both interim results')
                    self.state.record(dict(kind='dictation-live', stage='stop', language=selected, audio_bytes=audio_bytes))
                    self.live_result(final, True, detected)
                    self.live_result(final, True, detected)
                    self.live_frame(1, b'{"type":"Metadata"}')
                    self.state.record(dict(kind='dictation-live', stage='final', language=selected, audio_bytes=audio_bytes))
                    self.live_frame(8, struct.pack('!H', 1000))
                    return
                else:
                    raise ValueError('unexpected fixture frame')
        except (ConnectionError, OSError, ValueError) as error:
            self.state.record(dict(kind='dictation-live', stage='error', error=type(error).__name__))
