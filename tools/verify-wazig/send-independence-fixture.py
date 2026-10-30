import json
import re
import time
from urllib.parse import parse_qs, urlsplit


class SendIndependenceHandler(Handler):
    def do_GET(self):
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/messages' and query.get('chat') == [ALPHA]:
            if not self.authorized():
                return
            with self.state.lock:
                armed = getattr(self.state, 'send_independence_armed', False)
                self.state.send_independence_armed = False
            if armed:
                self.state.record({'phase': 'history-start', 'monotonic_ns': time.monotonic_ns()})
                gate = self.state.send_independence_gate
                released = gate.wait(timeout=5)
                self.state.record({'phase': 'history-release', 'monotonic_ns': time.monotonic_ns(), 'manual': released})
                self.wire_path = self.path
                self.respond(200, [{'MsgID': 'INDEPENDENCE-HISTORY', 'ChatJID': ALPHA,
                                    'Timestamp': self.state.stamp, 'Text': 'Independent history',
                                    'DisplayText': 'Independent history', 'FromMe': False,
                                    'SenderName': 'Fixture Sender', 'SenderJID': 'fixture-sender'}])
                return
        super().do_GET()

    def do_POST(self):
        if self.path == '/fixture/arm-send-independence':
            self.wire_path = self.path
            if not self.authorized():
                return
            self.rfile.read(int(self.headers.get('Content-Length', '0')))
            with self.state.lock:
                self.state.send_independence_armed = True
                self.state.send_independence_gate = bridge.threading.Event()
            self.respond(200, {'armed': True})
            return
        if self.path == '/v1/wazig/send':
            self.wire_path = self.path
            if not self.authorized():
                return
            body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
            client_id = body.get('client_id', '')
            if set(body) != {'chat', 'text', 'reply_to', 'client_id'} or body.get('chat') != ALPHA or body.get('text') != 'Independent fixture text' or body.get('reply_to') != '' or not re.fullmatch(r'[0-9a-f]{32}', client_id):
                self.respond(400, {'error': 'unexpected synthetic send'}, body=body)
                return
            with self.state.lock:
                duplicate = client_id in self.state.sends
                if not duplicate:
                    self.state.sends[client_id] = {'client_id': client_id, 'msg_id': 'INDEPENDENCE-SENT', 'ts': self.state.stamp, 'status': 'sent'}
                reply = self.state.sends[client_id]
            self.state.record({'phase': 'send-accepted', 'monotonic_ns': time.monotonic_ns(), 'client_id': client_id, 'canonical_id': reply['msg_id'], 'duplicate': duplicate})
            self.respond(200, reply, body=body, accepted=not duplicate, duplicate=duplicate)
            return
        super().do_POST()
