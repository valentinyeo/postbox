class SendOnceHandler(Handler):
    def do_GET(self):
        url = urlsplit(self.path)
        if url.path != '/v1/wazig/messages':
            super().do_GET()
            return
        self.wire_path = self.path
        if not self.authorized():
            return
        chat = parse_qs(url.query).get('chat', [''])[0]
        rows = [dict(MsgID='ONCE-HISTORY', ChatJID=chat, Timestamp=self.state.stamp,
                     Text='Send once history', DisplayText='Send once history', FromMe=False,
                     SenderName='Fixture Sender', SenderJID='fixture-sender')]
        with self.state.lock:
            for sent in self.state.sends.values():
                if sent['chat'] != chat:
                    continue
                rows.insert(0, dict(MsgID=sent['msg_id'], ChatJID=chat, Timestamp=sent['ts'],
                                    Text=sent['text'], DisplayText=sent['text'], FromMe=True,
                                    SenderName='You', SenderJID='fixture-self'))
        self.respond(200, rows)

    def do_POST(self):
        if self.path != '/v1/wazig/send':
            super().do_POST()
            return
        self.wire_path = self.path
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
        if (set(body) != {'chat', 'text', 'reply_to', 'client_id'} or body['chat'] not in (ALPHA, BETA) or
                body['reply_to'] != '' or not body['text'].startswith('Once ')):
            self.respond(400, {'error': 'unexpected send-once write'}, body=body)
            return
        with self.state.lock:
            duplicate = body['client_id'] in self.state.sends
            if not duplicate:
                self.state.sends[body['client_id']] = dict(
                    body, msg_id='ONCE-SENT-%d' % (len(self.state.sends) + 1), ts=self.state.stamp, status='sent')
            sent = self.state.sends[body['client_id']]
        self.respond(200, {k: sent[k] for k in ('client_id', 'msg_id', 'ts', 'status')},
                     body=body, accepted=not duplicate, duplicate=duplicate)
