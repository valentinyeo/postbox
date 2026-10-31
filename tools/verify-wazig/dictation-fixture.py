import json
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
        if not self.authorized():
            return
        url = urlsplit(self.path)
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
