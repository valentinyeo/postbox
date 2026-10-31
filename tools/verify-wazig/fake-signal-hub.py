import mimetypes


SIGNAL_CHAT = 'signal:fixture-contact'
SIGNAL_LIMITED = 'signal:fixture-limited'
SIGNAL_CAPTCHA = 'signal:fixture-captcha'


class SignalHandler(Handler):
    def respond(self, status, data, content_type='application/json', **extra):
        bridge.Handler.respond(self, status, data, content_type, **extra)

    def event(self, event_id, kind, chat):
        data = dict(id=event_id, chat=SIGNAL_CHAT if chat else '', ts=self.state.stamp, kind=kind)
        self.wfile.write(f'id: {event_id}\ndata: {json.dumps(data)}\n\n'.encode())
        self.wfile.flush()
        self.state.record(dict(method='SSE', path='/v1/wazig/events', wire_path=self.wire_path, **data))

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
                pending = [(index + 2, event) for index, event in enumerate(self.state.signal_events) if index + 2 > last]
                if not pending:
                    self.state.lock.wait(timeout=2)
            if pending:
                for event_id, (kind, chat) in pending:
                    self.event(event_id, kind, chat)
                self.close_connection = True
                return
            self.wfile.write(b': heartbeat\n\n')
            self.wfile.flush()

    def publish(self, kind, chat=SIGNAL_CHAT):
        with self.state.lock:
            self.state.signal_events.append((kind, chat))
            self.state.lock.notify_all()

    def message(self, chat, message_id, text, **extra):
        return dict(MsgID=message_id, ChatJID=chat, Text=text, DisplayText=text,
                    Timestamp=self.state.stamp, SenderJID='fixture-sender', SenderName='Fixture Sender',
                    FromMe=extra.pop('FromMe', False), **extra)

    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            rows = []
            if query.get('archived', ['false'])[0] == 'false':
                rows = [dict(provider='signal', jid=chat, name=name, kind=kind,
                             last_message_ts=self.state.stamp, unread_count=0 if chat in self.state.signal_read else 1,
                             unread=chat not in self.state.signal_read, archived=False)
                        for chat, name, kind in [(SIGNAL_CHAT, 'Verification Signal', 'direct'),
                                                 (SIGNAL_LIMITED, 'Verification Limited', 'direct'),
                                                 (SIGNAL_CAPTCHA, 'Verification Captcha', 'direct'),
                                                 ('signal:group:fixture-group', 'Verification Group', 'group')]]
            self.respond(200, rows)
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            rows = [self.message(chat, 'fixture-sender:1000', 'Synthetic Signal history')]
            if chat == SIGNAL_CHAT:
                rows.append(self.message(chat, 'fixture-sender:1001', 'Synthetic Signal attachment',
                                         MediaType='image', MimeType='image/png', Filename='fixture.png'))
                if self.state.live:
                    rows.append(self.message(chat, 'fixture-sender:1002', 'Synthetic Signal live'))
                with self.state.lock:
                    rows.extend(self.message(chat, reply['msg_id'], reply['text'], FromMe=True,
                                             **({'quoted_msg_id': reply['reply_to']} if reply['reply_to'] else {}),
                                             **(dict(MediaType=reply['media_type'], Filename=reply['filename'],
                                                     MimeType=reply['mime_type']) if reply['file'] else {}))
                                for reply in self.state.sends.values() if reply['chat'] == chat)
                    if self.state.signal_reaction:
                        rows.append(self.message(chat, 'fixture-reaction:1003', '',
                                                 ReactionToID=self.state.signal_reaction['msg'],
                                                 ReactionEmoji=self.state.signal_reaction['emoji']))
            self.respond(200, list(reversed(rows)))
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path.startswith('/v1/wazig/media/'):
            self.respond(200, self.state.image, 'image/png')
        elif url.path.startswith('/v1/wazig/avatar/'):
            self.respond(404, {'error': 'unavailable'})
        else:
            self.respond(404, {'error': 'unknown signal route'})

    def do_POST(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        payload = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        multipart = self.headers.get('Content-Type', '').startswith('multipart/form-data')
        file_bytes = b''
        filename, mime_type = '', ''
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
                    file_bytes = part.get_payload(decode=True)
                    filename, mime_type = part.get_filename(), part.get_content_type()
        else:
            body = json.loads(payload or '{}')
        if self.path == '/fixture/live':
            with self.state.lock:
                self.state.live = True
                self.state.lock.notify_all()
            self.publish('msg')
            self.respond(200, {'ok': True}, body=body)
            return
        if multipart and mime_type == 'application/octet-stream':
            mime_type = mimetypes.guess_type(filename)[0] or mime_type
        chat = body.get('chat', '')
        if not chat.startswith('signal:'):
            self.respond(400, {'error': 'invalid Signal chat'}, body=body)
        elif self.path == '/v1/wazig/send':
            if chat == SIGNAL_LIMITED:
                self.respond(429, {'error': 'signal rate limited', 'retry_after': 30}, body=body)
                return
            if chat == SIGNAL_CAPTCHA:
                self.respond(403, {'error': 'signal captcha required'}, body=body)
                return
            expected = {'chat', 'text', 'reply_to', 'client_id'} if not multipart else {'chat', 'text', 'file', 'client_id'}
            if not expected.issubset(body) or not body['client_id'] or (multipart and not file_bytes):
                self.respond(400, {'error': 'invalid Signal send'}, body=body)
                return
            with self.state.lock:
                duplicate = body['client_id'] in self.state.sends
                if not duplicate:
                    self.state.sends[body['client_id']] = dict(client_id=body['client_id'],
                        msg_id=f'fixture-self:{2000 + len(self.state.sends)}', ts=self.state.stamp,
                        status='sent', chat=chat, text=body['text'], file=multipart,
                        reply_to=body.get('reply_to', ''), filename=filename, mime_type=mime_type,
                        media_type=mime_type.split('/')[0] if mime_type.startswith(('image/', 'video/', 'audio/')) else 'document')
                reply = self.state.sends[body['client_id']]
            if not duplicate:
                self.publish('msg', chat)
            self.respond(200, reply, body=body, multipart=multipart, file_size=len(file_bytes),
                         file_sha256=bridge.hashlib.sha256(file_bytes).hexdigest(), accepted=not duplicate)
        elif self.path == '/v1/wazig/react' and set(body) == {'chat', 'msg', 'emoji', 'client_id'}:
            self.state.signal_reaction = body
            self.publish('reaction', chat)
            self.respond(200, dict(client_id=body['client_id'], msg_id='fixture-reaction:1003',
                                   ts=self.state.stamp, status='sent'), body=body)
        elif self.path == '/v1/wazig/mark-read' and set(body) == {'chat', 'message_id'}:
            self.state.signal_read.add(chat)
            self.publish('read', chat)
            self.respond(200, {'status': 'ok'}, body=body)
        elif self.path == '/v1/wazig/archive':
            self.respond(502, {'error': 'Signal archive unsupported'}, body=body)
        else:
            self.respond(400, {'error': 'invalid Signal write'}, body=body)


