import json
import re
import time
from urllib.parse import parse_qs, urlsplit


class SendIndependenceHandler(Handler):
    def phase(self, name, **values):
        with self.state.lock:
            sequence = getattr(self.state, 'send_independence_sequence', 0) + 1
            self.state.send_independence_sequence = sequence
            event = dict(phase=name, sequence=sequence, perf_counter_ns=time.perf_counter_ns(), **values)
            self.state.record(event)
            return event

    def do_GET(self):
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/messages' and query.get('chat') == [ALPHA]:
            self.wire_path = self.path
            if not self.authorized():
                return
            with self.state.lock:
                armed = getattr(self.state, 'send_independence_armed', False)
                self.state.send_independence_armed = False
                if armed:
                    self.state.send_independence_held = True
                    info = time.get_clock_info('perf_counter')
                    self.phase('history-start', clock_resolution_seconds=info.resolution,
                               clock_monotonic=info.monotonic, clock_adjustable=info.adjustable)
            if armed:
                released = self.state.send_independence_gate.wait(timeout=5)
                with self.state.lock:
                    self.state.send_independence_held = False
                    self.phase('history-release', manual=released)
            with self.state.lock:
                deliveries = list(getattr(self.state, 'send_independence_deliveries', {}).values())
            rows = [{'MsgID': 'INDEPENDENCE-HISTORY', 'ChatJID': ALPHA,
                     'Timestamp': self.state.stamp, 'Text': 'Independent history',
                     'DisplayText': 'Independent history', 'FromMe': False,
                     'SenderName': 'Fixture Sender', 'SenderJID': 'fixture-sender'}]
            for delivery in deliveries:
                rows.append({'MsgID': delivery['msg_id'], 'ChatJID': ALPHA,
                             'Timestamp': delivery['ts'], 'Text': 'Independent fixture text',
                             'DisplayText': 'Independent fixture text', 'FromMe': True,
                             'SenderName': 'Fixture Self', 'SenderJID': 'fixture-self'})
            self.respond(200, rows)
            return
        super().do_GET()

    def do_POST(self):
        if self.path in ('/fixture/arm-send-independence', '/fixture/mark-send-independence'):
            self.wire_path = self.path
            if not self.authorized():
                return
            self.rfile.read(int(self.headers.get('Content-Length', '0')))
            with self.state.lock:
                if self.path.endswith('arm-send-independence'):
                    self.state.send_independence_armed = True
                    self.state.send_independence_gate = bridge.threading.Event()
                    result = {'armed': True}
                else:
                    held = getattr(self.state, 'send_independence_held', False)
                    result = self.phase('submit-marker', held=held)
            self.respond(200, result)
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
                if not hasattr(self.state, 'send_independence_deliveries'):
                    self.state.send_independence_deliveries = {}
                deliveries = self.state.send_independence_deliveries
                duplicate = client_id in deliveries
                if not duplicate:
                    deliveries[client_id] = {'client_id': client_id, 'msg_id': 'INDEPENDENCE-SENT', 'ts': self.state.stamp, 'status': 'sent'}
                reply = deliveries[client_id]
                self.phase('send-accepted', client_id=client_id, canonical_id=reply['msg_id'], duplicate=duplicate)
            self.respond(200, reply, body=body, accepted=not duplicate, duplicate=duplicate)
            return
        super().do_POST()
