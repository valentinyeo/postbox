class ReplyHandler(Handler):
    def do_GET(self):
        url = urlsplit(self.path)
        if url.path != '/v1/wazig/messages':
            super().do_GET()
            return
        self.wire_path = self.path
        if not self.authorized():
            return
        chat = parse_qs(url.query).get('chat', [''])[0]
        rows = [dict(MsgID='REPLY-ORIGINAL', ChatJID=chat, Timestamp=self.state.stamp,
                     Text='First words of the original\nSecond line stays out of the preview',
                     FromMe=False, SenderName='Fixture Sender', SenderJID='fixture-sender')]
        with self.state.lock:
            for reply in self.state.sends.values():
                if reply['chat'] != chat:
                    continue
                rows.insert(0, dict(MsgID=reply['msg_id'], ChatJID=chat, Timestamp=reply['ts'],
                                   Text=reply['text'], FromMe=True, SenderName='You',
                                   quoted_msg_id=reply['reply_to'], quoted_sender_jid='fixture-sender',
                                   DisplayText='> First words of the original\n' + reply['text']))
        self.respond(200, rows)

    def do_POST(self):
        if self.path != '/v1/wazig/send':
            super().do_POST()
            return
        self.wire_path = self.path
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
        if (set(body) != {'chat', 'text', 'reply_to', 'client_id'} or
                body['chat'] not in (ALPHA, BETA) or body['reply_to'] != 'REPLY-ORIGINAL'):
            self.respond(400, {'error': 'wrong reply target'}, body=body)
            return
        with self.state.lock:
            self.state.sends[body['client_id']] = dict(body, msg_id='REPLY-SENT', ts=self.state.stamp, status='sent')
            result = self.state.sends[body['client_id']]
        self.respond(200, result, body=body)
