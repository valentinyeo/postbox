class DeepLinksHandler(VoiceHandler):
    chats = [
        ('personal:15550000101@s.whatsapp.net', 'Verification Personal', 'whatsapp', 'personal', '', 'direct'),
        ('business:15550000101@s.whatsapp.net', 'Verification Business', 'whatsapp', 'business', '', 'direct'),
        ('slack:T0ALPHA1:C0LAUNCH1', 'launch-notes', 'slack', 'T0ALPHA1', 'Alpha Workspace', 'channel'),
        ('slack:T0BETA22:C0LAUNCH1', 'launch-notes-beta', 'slack', 'T0BETA22', 'Beta Workspace', 'channel'),
    ]

    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            rows = [] if query.get('archived') == ['true'] else [
                dict(jid=jid, name=name, provider=provider, account=account, team_name=team_name, kind=kind,
                     last_message_ts=self.stamp(100 - index * 10), unread_count=0, archived=False)
                for index, (jid, name, provider, account, team_name, kind) in enumerate(self.chats)]
            self.respond(200, rows)
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            rows = []
            if chat == 'personal:15550000101@s.whatsapp.net':
                for n in range(1, 36):
                    msg_id = 'personal:WA-TARGET-MSG' if n == 5 else f'personal:WA-MSG-{n:02d}'
                    text = 'Targeted WhatsApp anchor message for deep link scroll proof' if n == 5 else f'Personal WhatsApp line {n} with enough text to fill the viewport height reliably.'
                    rows.append(dict(MsgID=msg_id, ChatJID=chat, Timestamp=self.stamp(n),
                                     Text=text, DisplayText=text, FromMe=(n % 3 == 0),
                                     SenderName='You' if n % 3 == 0 else 'Verification Personal',
                                     SenderJID='15550000101@s.whatsapp.net'))
            elif chat == 'business:15550000101@s.whatsapp.net':
                for n in range(1, 10):
                    text = f'Business WhatsApp account message {n} distinct from personal account.'
                    rows.append(dict(MsgID=f'business:BIZ-MSG-{n:02d}', ChatJID=chat, Timestamp=self.stamp(n),
                                     Text=text, DisplayText=text, FromMe=False,
                                     SenderName='Verification Business', SenderJID='15550000101@s.whatsapp.net'))
            elif chat == 'slack:T0ALPHA1:C0LAUNCH1':
                for n in range(1, 36):
                    ts = f'17000000{n:02d}.000100'
                    text = 'Targeted Slack message time for deep link scroll proof' if n == 5 else f'Alpha Workspace Slack update {n} with extra detail to require scrolling.'
                    rows.append(dict(MsgID=ts, ChatJID=chat, Timestamp=self.stamp(n),
                                     Text=text, DisplayText=text, FromMe=(n % 4 == 0),
                                     SenderName='You' if n % 4 == 0 else 'Fixture Teammate',
                                     SenderJID='U0ALPHA1'))
            elif chat == 'slack:T0BETA22:C0LAUNCH1':
                for n in range(1, 8):
                    ts = f'17000000{n:02d}.000200'
                    text = f'Beta Workspace Slack update {n}.'
                    rows.append(dict(MsgID=ts, ChatJID=chat, Timestamp=self.stamp(n),
                                     Text=text, DisplayText=text, FromMe=False,
                                     SenderName='Beta Teammate', SenderJID='U0BETA22'))
            self.respond(200, list(reversed(rows)))
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        else:
            self.respond(404, {'error': 'unavailable'})

    def do_POST(self):
        self.wire_path = urlsplit(self.path).path
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        if self.wire_path == '/v1/wazig/mark-read':
            self.respond(200, {'status': 'ok'}, body=body)
            return
        self.respond(403, {'error': 'unexpected write'}, body=body)
