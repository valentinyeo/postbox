class InlineLinksHandler(VoiceHandler):
    chats = [
        (ALPHA, 'Verification Inline WhatsApp', 'whatsapp', 'personal'),
        ('slack:fixture-inline:channel', 'Verification Inline Slack', 'slack', 'fixture-inline'),
        ('signal:fixture-inline', 'Verification Inline Signal', 'signal', 'signal'),
        ('telegram:user:7199', 'Verification Inline Telegram', 'telegram', 'telegram'),
    ]

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
                dict(jid=jid, name=name, provider=provider, account=account, kind='direct',
                     last_message_ts=self.stamp(10 - index), unread_count=0, archived=False)
                for index, (jid, name, provider, account) in enumerate(self.chats)]
            self.respond(200, rows)
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            provider = next((row[2] for row in self.chats if row[0] == chat), None)
            if not provider:
                self.respond(200, [])
                return
            body_url = origin + '/inline-links/' + provider + '-body-' + 'abcdefghij' * 18
            quote_url = origin + '/inline-links/' + provider + '-quote-' + 'klmnopqrst' * 18
            fallback_url = origin + '/inline-links/' + provider + '-fallback-' + 'uvwxyzabcd' * 18
            rows = [
                dict(MsgID='INLINE-BODY', Text='Synthetic text ' + body_url, Timestamp=self.stamp(1)),
                dict(MsgID='INLINE-PLAIN', Text='Synthetic ordinary text without a link', Timestamp=self.stamp(2)),
                dict(MsgID='INLINE-REPLY', Text='Synthetic incoming reply', DisplayText='> ' + quote_url + '\nSynthetic incoming reply',
                     quoted_msg_id='INLINE-BODY', quoted_sender_jid='fixture-sender', Timestamp=self.stamp(3)),
                dict(MsgID='INLINE-OUT', Text='Synthetic outgoing reply', DisplayText='> ' + quote_url + '\nSynthetic outgoing reply',
                     quoted_msg_id='INLINE-BODY', quoted_sender_jid='fixture-sender', FromMe=True, Timestamp=self.stamp(4)),
                dict(MsgID='INLINE-BLOCK', Text='Synthetic shared message', fixture_quote='Shared ' + fallback_url,
                     fixture_quote_sender='Fixture Sender', Timestamp=self.stamp(5)),
            ]
            for row in rows:
                row.update(ChatJID=chat, SenderName='Fixture Sender', SenderJID='fixture-sender')
                row.setdefault('FromMe', False)
            self.respond(200, list(reversed(rows)))
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        else:
            self.respond(404, {'error': 'unavailable'})

    def reject_write(self):
        self.wire_path = urlsplit(self.path).path
        self.record(403)
        self.close_connection = True
        self.send_response(403)
        self.send_header('Content-Length', '0')
        self.send_header('Connection', 'close')
        self.end_headers()

    def do_POST(self):
        self.wire_path = urlsplit(self.path).path
        if self.wire_path != '/v1/wazig/mark-read':
            self.reject_write()
            return
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        self.respond(200, {'status': 'ok'}, body=body)

    do_PUT = reject_write
    do_PATCH = reject_write
    do_DELETE = reject_write
