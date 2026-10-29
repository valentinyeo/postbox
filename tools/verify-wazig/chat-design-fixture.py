from urllib.parse import parse_qs, urlsplit


class ChatDesignHandler(Handler):
    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            self.respond(200, [] if query.get('archived') == ['true'] else [
                dict(jid='fixture-alpha', name='Graphite team', provider='slack', kind='group', last_message_ts=self.state.stamp,
                     last_message_preview='Source formatting, calm spacing', unread_count=2, archived=False),
                dict(jid='fixture-beta', name='Graphite direct', provider='whatsapp', kind='direct', last_message_ts=self.stamp(-1),
                     last_message_preview='The same look on WhatsApp', unread_count=0, archived=False)])
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            body = ('*Traffic* 2,124 sessions\n_And the drum roll says..._ *12 new subscribers!*\n'
                    '> *Traffic* · 2,124 sessions\n> *1,215* with consent · 909 without\n>\n> *Plans*\n> Upfront 8 · Monthly 4\n'
                    '- A list with a hanging indent that keeps wrapped words aligned with the text, never the marker.\n'
                    '1. Another item\nA ~removed~ word, `inline code` and @team\nSent using Claude')
            rows = [dict(MsgID='DESIGN-MAIN', Text=body, FromMe=False, SenderName='Fixture Sender', SenderJID='fixture-sender'),
                    dict(MsgID='DESIGN-SAME', Text='Short follow-up', FromMe=False, SenderName='Fixture Sender', SenderJID='fixture-sender'),
                    dict(MsgID='DESIGN-OWN', Text='Thank you! *Great result.*', FromMe=True, SenderName='You'),
                    dict(MsgID='DESIGN-LONG', Text='A longer reply stays inside the same centred chat column. ' * 2, FromMe=True, SenderName='You')]
            for index, row in enumerate(rows):
                row.update(ChatJID=chat, Timestamp=self.stamp(index))
            self.respond(200, list(reversed(rows)))
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        elif url.path.startswith('/v1/wazig/avatar/'):
            self.respond(404, {'error': 'unavailable'})
        else:
            self.respond(404, {'error': 'unavailable'})
