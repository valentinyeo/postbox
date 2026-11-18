from real_size_seed import CHATS, MANIFEST, MESSAGES


class RealSizeHandler(ArchiveInboxHandler):
    def do_GET(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if url.path == '/fixture/seed':
            self.respond(200, MANIFEST, seed=MANIFEST)
        elif url.path == '/v1/wazig/chats':
            rows = [row for row in CHATS if row['archived'] == (query.get('archived') == ['true'])]
            self.respond(200, rows, rows=rows)
        elif url.path == '/v1/wazig/messages':
            chat = query.get('chat', [''])[0]
            if chat not in MESSAGES:
                self.respond(404, {'error': 'unknown seed chat'})
                return
            rows = list(reversed(MESSAGES[chat]))
            before = query.get('before', [''])[0]
            if before:
                position = next((n for n, row in enumerate(rows) if before == row['MsgID'] + ':' + row['Timestamp']), None)
                if position is None:
                    self.respond(400, {'error': 'unknown seed cursor'})
                    return
                rows = rows[position + 1:]
            limit = min(int(query.get('limit', ['80'])[0]), 1600)
            rows = rows[:limit]
            self.respond(200, rows, chat=chat, message_ids=[row['MsgID'] for row in rows])
        elif url.path.startswith('/v1/wazig/media/'):
            parts = url.path.removeprefix('/v1/wazig/media/').split('/', 1)
            if len(parts) != 2:
                self.respond(404, {'error': 'unknown seed media'})
                return
            chat, message = map(unquote, parts)
            row = next((row for row in MESSAGES.get(chat, []) if row['MsgID'] == message), None)
            if row is None or 'MediaType' not in row:
                self.respond(404, {'error': 'unknown seed media'})
                return
            payload = {'audio': VOICE_BYTES, 'image': self.state.image, 'document': b'Synthetic seeded document\n'}[row['MediaType']]
            self.respond(200, payload, row['MimeType'], sha256=hashlib.sha256(payload).hexdigest())
        elif url.path == '/v1/wazig/groups':
            self.respond(200, [dict(JID=row['jid'], Name=row['name']) for row in CHATS
                               if row['provider'] == 'whatsapp' and row['kind'] == 'group'])
        elif url.path == '/v1/wazig/events':
            self.events()
        else:
            self.respond(404, {'error': 'unavailable'})

    def do_POST(self):
        self.wire_path = self.path
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        if self.path == '/v1/wazig/mark-read' and body.get('chat') in MESSAGES:
            self.respond(200, {'status': 'ok'}, body=body)
        else:
            self.respond(400, {'error': 'unexpected real-size write'}, body=body)
