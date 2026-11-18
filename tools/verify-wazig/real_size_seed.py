from datetime import datetime, timedelta, timezone
import json


CHATS = []
MESSAGES = {}
END = datetime(2026, 10, 30, 12, tzinfo=timezone.utc)

for index in range(320):
    slack = index >= 312
    group = 272 <= index < 312
    jid = (f'slack:TSEED:C{index:010}' if slack else
           f'personal:1555000{index:04}{"@g.us" if group else "@s.whatsapp.net"}')
    label = 'Busy' if index == 0 else 'Voice' if index == 1 else f'{"Group" if group else "Channel" if slack else "Direct"} {index:03}'
    name = f'{"Orchard" if index % 4 == 0 or index == 1 else "Seed"} {label}'
    end = END - timedelta(minutes=index)
    count = 1600 if index == 0 else 16
    rows = []
    for number in range(count):
        stamp = end - timedelta(seconds=(count - 1 - number) * (60 * 86400) // (count - 1))
        text = f'Synthetic orchard update {index:03}/{number:04}'
        row = dict(MsgID=f'SEED-{index:03}-{number:04}', ChatJID=jid,
                   Timestamp=stamp.isoformat(timespec='seconds').replace('+00:00', 'Z'),
                   Text=text, DisplayText=text, FromMe=number % 5 == 4,
                   SenderName=f'Seed Sender {number % 4 + 1:02}', SenderJID=f'seed-sender-{number % 4 + 1}')
        if index and number in (3, 7, 11, 15):
            kind, mime, filename = {
                3: ('image', 'image/png', 'seed.png'),
                7: ('document', 'text/plain', 'seed.txt'),
                11: ('image', 'image/png', 'seed.png'),
                15: ('audio', 'audio/ogg', 'voice-note.ogg'),
            }[number]
            row.update(MediaType=kind, MimeType=mime, Filename=filename, Text='', DisplayText='')
        elif number and number % 7 == 0:
            row.update(quoted_msg_id=rows[-1]['MsgID'], quoted_sender_jid=rows[-1]['SenderJID'],
                       DisplayText='> ' + rows[-1]['Text'] + '\n' + text)
        rows.append(row)
    MESSAGES[jid] = rows
    CHATS.append(dict(jid=jid, provider='slack' if slack else 'whatsapp',
                      account='TSEED' if slack else 'personal', name=name,
                      kind='group' if group or slack else 'direct',
                      last_message_ts=rows[-1]['Timestamp'], unread_count=3 if index % 6 == 0 else 0,
                      unread=index % 6 == 0, archived=280 <= index < 300))

COUNTS = dict(chats=len(CHATS), messages=sum(map(len, MESSAGES.values())),
              voice=sum(row.get('MediaType') == 'audio' for rows in MESSAGES.values() for row in rows),
              images=sum(row.get('MediaType') == 'image' for rows in MESSAGES.values() for row in rows),
              groups=sum(chat['provider'] == 'whatsapp' and chat['kind'] == 'group' for chat in CHATS))
BUSY = max(MESSAGES, key=lambda chat: len(MESSAGES[chat]))
VOICE = CHATS[1]['jid']
GROUP = CHATS[272]['jid']
INBOX = [chat for chat in CHATS if not chat['archived']]
ARCHIVED = [chat for chat in CHATS if chat['archived']]
SEARCH = [chat for chat in INBOX if 'orchard' in chat['name'].lower()]
MANIFEST = dict(counts=COUNTS, inbox=len(INBOX), archived=len(ARCHIVED), busy=BUSY, voice=VOICE,
                group=GROUP, busy_messages=len(MESSAGES[BUSY]), search='Orchard', search_count=len(SEARCH))


if __name__ == '__main__':
    print(json.dumps(MANIFEST, sort_keys=True))
