class SearchHandler(PaletteArchivedHandler):
    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        fixture = json.loads(Path(__file__).with_name('search-queries.json').read_text(encoding='utf-8'))
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/v1/wazig/chats':
            self.respond(200, [row for row in fixture['rows'] if row['archived'] == (query.get('archived') == ['true'])])
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            row = next(row for row in fixture['rows'] if row['jid'] == chat)
            self.respond(200, [dict(MsgID='SEARCH-HISTORY', ChatJID=chat, Timestamp=row['last_message_ts'],
                                   Text=fixture['message'], FromMe=True, SenderName='Fixture Sender')])
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [])
        elif url.path == '/v1/wazig/events':
            self.events()
        else:
            self.respond(404, {'error': 'unavailable'})
