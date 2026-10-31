from urllib.parse import parse_qs, urlsplit


class IconHintsHandler(VoiceHandler):
    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            self.respond(200, [] if query.get('archived') == ['true'] else [
                dict(jid='fixture-alpha', name='Fixture Slack', provider='slack', kind='group', last_message_ts=self.state.stamp, unread_count=0, archived=False),
                dict(jid='fixture-beta', name='Fixture WhatsApp', provider='whatsapp', kind='direct', last_message_ts=self.stamp(-1), unread_count=0, archived=False),
            ])
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            rows = [dict(MsgID=f'ICON-{index:02}', ChatJID=chat, Timestamp=self.stamp(index - 24),
                         Text=f'Synthetic message {index:02}', FromMe=index % 2 == 0,
                         SenderName='Fixture sender', SenderJID='fixture-sender') for index in range(24)]
            self.respond(200, list(reversed(rows)))
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        elif url.path.startswith('/v1/wazig/avatar/'):
            self.respond(404, {'error': 'unavailable'})
        else:
            self.respond(404, {'error': 'unavailable'})
