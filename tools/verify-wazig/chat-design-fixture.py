from urllib.parse import parse_qs, urlsplit


class ChatDesignHandler(VoiceHandler):
    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            self.respond(200, [] if query.get('archived') == ['true'] else [
                dict(jid='fixture-alpha', name='Graphite team', provider='slack', kind='group', last_message_ts=self.state.stamp,
                     unread_count=2, archived=False),
                dict(jid='fixture-beta', name='Graphite group', provider='whatsapp', kind='group', last_message_ts=self.stamp(-1),
                     unread_count=0, archived=False)])
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            body = ('*Traffic* 2,124 sessions\n_And the drum roll says..._ *12 new subscribers!*\n'
                    '> *Traffic* · 2,124 sessions\n> *1,215* with consent · 909 without\n>\n> *Plans*\n> Upfront 8 · Monthly 4\n'
                    '- A list with a hanging indent that keeps wrapped words aligned with the text, never the marker.\n'
                    '1. Another item\nA ~removed~ word, `inline code` and @team\nSent using Claude')
            rows = [dict(MsgID='DESIGN-MAIN', Text=body, FromMe=False, SenderName='Fixture Sender', SenderJID='fixture-sender'),
                    dict(MsgID='DESIGN-SAME', Text='Short follow-up', FromMe=False, SenderName='Fixture Sender', SenderJID='fixture-sender'),
                    dict(MsgID='DESIGN-OWN', Text='OK', FromMe=True, SenderName='You'),
                    dict(MsgID='DESIGN-LONG', Text='A longer reply stays inside the same centred chat column. ' * 2, FromMe=True, SenderName='You')]
            for index, row in enumerate(rows):
                row.update(ChatJID=chat, Timestamp=self.stamp(index))
            if chat == 'fixture-beta':
                rows = [
                    dict(MsgID='GROUP-FIRST', Text='First note', SenderName='Alex', SenderJID='fixture-alex', Timestamp='2026-10-27T10:00:00Z'),
                    dict(MsgID='GROUP-SAME', Text='Close follow-up', SenderName='Alex', SenderJID='fixture-alex', Timestamp='2026-10-27T10:01:00Z'),
                    dict(MsgID='GROUP-DAY', Text='New day', SenderName='Alex', SenderJID='fixture-alex', Timestamp='2026-10-28T10:00:00Z'),
                    dict(MsgID='GROUP-OTHER', Text='Other sender', SenderName='Blair', SenderJID='fixture-blair', Timestamp='2026-10-28T10:01:00Z'),
                    dict(MsgID='GROUP-QUOTE', Text='Yes', SenderName='Blair', SenderJID='fixture-blair', Timestamp='2026-10-28T10:02:00Z',
                         quoted_msg_id='GROUP-DAY', quoted_sender_jid='fixture-alex', DisplayText='> New day\nYes'),
                    dict(MsgID='GROUP-OWN', Text='OK', SenderName='You', FromMe=True, Timestamp='2026-10-28T10:03:00Z'),
                ]
                for row in rows:
                    row.update(ChatJID=chat)
                    row.setdefault('FromMe', False)
            self.respond(200, list(reversed(rows)))
        elif url.path == '/v1/wazig/events':
            self.events()
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        elif url.path.startswith('/v1/wazig/avatar/'):
            self.respond(404, {'error': 'unavailable'})
        else:
            self.respond(404, {'error': 'unavailable'})
