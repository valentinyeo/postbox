class InlineLinksHandler(VoiceHandler):
    def do_GET(self):
        self.wire_path = self.path
        url = urlsplit(self.path)
        origin = f'http://127.0.0.1:{self.server.server_port}'
        if url.path.startswith('/inline-links/'):
            self.respond(200, b'<html><body>Synthetic local link</body></html>', 'text/html', user_agent=self.headers.get('User-Agent', ''))
            return
        if not self.authorized():
            return
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            rows = [] if query.get('archived') == ['true'] else [
                dict(jid=ALPHA, name='Verification Inline Links', provider='whatsapp', kind='direct',
                     last_message_ts=self.stamp(3), unread_count=0, archived=False),
                dict(jid=BETA, name='Verification Other', provider='whatsapp', kind='direct',
                     last_message_ts=self.stamp(0), unread_count=0, archived=False)]
            self.respond(200, rows)
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            if chat != ALPHA:
                self.respond(200, [])
                return
            body_url = origin + '/inline-links/body-' + 'abcdefghij' * 18
            quote_url = origin + '/inline-links/quote-' + 'klmnopqrst' * 18
            rows = [
                dict(MsgID='INLINE-BODY', Text=body_url, Timestamp=self.stamp(1)),
                dict(MsgID='INLINE-PLAIN', Text='Synthetic ordinary text without a link', Timestamp=self.stamp(2)),
                dict(MsgID='INLINE-REPLY', Text='Synthetic reply', DisplayText='> ' + quote_url + '\nSynthetic reply',
                     quoted_msg_id='INLINE-BODY', quoted_sender_jid='fixture-sender', Timestamp=self.stamp(3)),
            ]
            for row in rows:
                row.update(ChatJID=chat, FromMe=False, SenderName='Fixture Sender', SenderJID='fixture-sender')
            self.respond(200, list(reversed(rows)))
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        else:
            self.respond(404, {'error': 'unavailable'})

    def do_POST(self):
        self.wire_path = urlsplit(self.path).path
        if self.wire_path != '/v1/wazig/mark-read':
            self.record(403)
            self.close_connection = True
            self.send_response(403)
            self.send_header('Content-Length', '0')
            self.send_header('Connection', 'close')
            self.end_headers()
            return
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        self.respond(200, {'status': 'ok'}, body=body)
