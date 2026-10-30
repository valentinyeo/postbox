import json
import re
import time
from urllib.parse import parse_qs, urlsplit


class SendIndependenceHandler(Handler):
    def phase(self, name, **values):
        with self.state.lock:
            sequence = getattr(self.state, 'send_independence_sequence', 0) + 1
            self.state.send_independence_sequence = sequence
            values.setdefault('trial', getattr(self.state, 'send_independence_trial', 'baseline'))
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
                released = self.state.send_independence_gate.wait(timeout=getattr(self.state, 'send_independence_hold_seconds', 5))
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
                             'Timestamp': delivery['ts'], 'Text': delivery['text'],
                             'DisplayText': delivery['text'], 'FromMe': True,
                             'SenderName': 'Fixture Self', 'SenderJID': 'fixture-self'})
            self.respond(200, rows)
            return
        super().do_GET()

    def do_POST(self):
        if self.path in ('/fixture/arm-send-independence', '/fixture/mark-send-independence', '/fixture/switch-send-independence'):
            self.wire_path = self.path
            if not self.authorized():
                return
            body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or b'{}')
            with self.state.lock:
                if self.path.endswith('arm-send-independence'):
                    self.state.send_independence_armed = True
                    trial = body.get('trial', 'baseline')
                    if trial not in ('baseline', 'text', 'file'):
                        self.respond(400, {'error': 'unknown fixture trial'})
                        return
                    self.state.send_independence_trial = trial
                    self.state.send_independence_hold_seconds = 5 if trial == 'baseline' else 15
                    self.state.send_independence_gate = bridge.threading.Event()
                    self.state.send_independence_switch = bridge.threading.Event()
                    result = {'armed': True}
                elif self.path.endswith('switch-send-independence'):
                    self.state.send_independence_switch.set()
                    result = self.phase('switch-marker')
                else:
                    held = getattr(self.state, 'send_independence_held', False)
                    result = self.phase('submit-marker', held=held)
            self.respond(200, result)
            return
        if self.path == '/v1/wazig/send':
            self.wire_path = self.path
            if not self.authorized():
                return
            payload = self.rfile.read(int(self.headers.get('Content-Length', '0')))
            multipart = self.headers.get('Content-Type', '').startswith('multipart/form-data')
            image = b''
            if multipart:
                envelope = bridge.BytesParser(policy=bridge.policy.default).parsebytes(
                    f'Content-Type: {self.headers["Content-Type"]}\r\nMIME-Version: 1.0\r\n\r\n'.encode() + payload)
                body = {}
                for part in envelope.iter_parts():
                    name = part.get_param('name', header='content-disposition')
                    if part.get_filename() is None:
                        body[name] = part.get_content()
                    else:
                        body[name] = part.get_filename()
                        image = part.get_payload(decode=True)
            else:
                body = json.loads(payload)
            client_id = body.get('client_id', '')
            label = body.get('text')
            expected = {'account', 'chat', 'text', 'reply_to', 'client_id', 'ptt', 'file'} if multipart else {'chat', 'text', 'reply_to', 'client_id'}
            if set(body) != expected or body.get('chat') != ALPHA or label not in ('Independent fixture text', 'Independent fixture file') or body.get('reply_to') != '' or not re.fullmatch(r'[0-9a-f]{32}', client_id) or multipart != (label == 'Independent fixture file') or (multipart and (body.get('account') != 'hub' or not image.startswith(b'\x89PNG\r\n\x1a\n') or body.get('ptt') != 'false')):
                self.respond(400, {'error': 'unexpected synthetic send'}, body=body)
                return
            trial = getattr(self.state, 'send_independence_trial', 'baseline')
            if trial != 'baseline':
                self.capture_identity_ingress()
                self.capture_identity_snapshot(body)
            self.phase('send-arrived', trial=trial, client_id=client_id)
            if trial != 'baseline' and not self.state.send_independence_switch.wait(timeout=10):
                self.respond(408, {'error': 'fixture switch timeout'}, body=body)
                return
            with self.state.lock:
                if not hasattr(self.state, 'send_independence_deliveries'):
                    self.state.send_independence_deliveries = {}
                deliveries = self.state.send_independence_deliveries
                duplicate = client_id in deliveries
                canonical = 'INDEPENDENCE-FILE' if multipart else 'INDEPENDENCE-SENT'
                if not duplicate:
                    deliveries[client_id] = {'client_id': client_id, 'msg_id': canonical, 'ts': self.state.stamp, 'status': 'sent', 'text': label}
                delivery = deliveries[client_id]
                self.phase('send-accepted', trial=trial, client_id=client_id, canonical_id=delivery['msg_id'], duplicate=duplicate,
                           file_sha256=hashlib.sha256(image).hexdigest() if multipart else '', file_bytes=len(image), filename=body.get('file', ''))
                reply = {k: delivery[k] for k in ('client_id', 'msg_id', 'ts', 'status')}
            self.respond(200, reply, body=body, accepted=not duplicate, duplicate=duplicate)
            return
        super().do_POST()
