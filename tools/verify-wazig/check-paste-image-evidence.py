import re
import hashlib
import json
from pathlib import Path
import struct
import zlib


def check_paste_image(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'paste-image' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='paste-image', status='passed')
    assert not (folder / 'failure.txt').exists()
    expected = [(provider, width, height, 'both') for provider in ('whatsapp', 'slack', 'signal', 'telegram')
                for width, height in ((1920, 1032), (3840, 2160))]
    expected.extend(('whatsapp', 1920, 1032, mode) for mode in ('v5', 'png', 'dib24', 'rgb32', 'bitmap'))
    sizes = read('sizes.json')
    assert [(row['provider'], row['width'], row['height'], row['mode']) for row in sizes] == expected
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
    assert all(row['wire_path'].startswith('/v1/wazig/') for row in requests)
    sends = [row for row in requests if row['path'] == '/v1/wazig/send']
    assert len(sends) == len(sizes) and len({row['body']['client_id'] for row in sends}) == len(sizes)
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert actions.count('keys: ^v\n') == len(sizes)
    for index, (size, send) in enumerate(zip(sizes, sends), 1):
        assert size['case'] == index
        assert send['accepted'] and send['status'] == 200 and send['multipart']
        assert send['body']['chat'] == 'paste:' + size['provider'] and send['body']['text'] == ''
        assert send['body']['file'].endswith('.png')
        assert send['body']['client_id'] == size['client_id']
        assert size['raw_bytes'] == size['width'] * size['height'] * 4
        assert size['upload'] == send['upload'] == 'paste-uploads/' + size['client_id'] + '.png'
        raw = (folder / size['upload']).read_bytes()
        assert len(raw) == size['file_size'] == send['file_size']
        assert hashlib.sha256(raw).hexdigest() == size['sha256'] == send['file_sha256']
        assert raw.startswith(b'\x89PNG\r\n\x1a\n')
        offset, compressed, header = 8, bytearray(), None
        while offset < len(raw):
            length = struct.unpack_from('>I', raw, offset)[0]
            kind = raw[offset + 4:offset + 8]
            data = raw[offset + 8:offset + 8 + length]
            assert zlib.crc32(kind + data) == struct.unpack_from('>I', raw, offset + 8 + length)[0]
            if kind == b'IHDR':
                header = struct.unpack('>IIBBBBB', data)
            elif kind == b'IDAT':
                compressed.extend(data)
            offset += length + 12
            if kind == b'IEND':
                break
        width, height, depth, colour, compression, filtering, interlace = header
        assert (width, height) == (size['width'], size['height'])
        assert depth == 8 and colour in (2, 6) and compression == filtering == interlace == 0
        channels = 3 if colour == 2 else 4
        assert len(zlib.decompress(compressed)) == (width * channels + 1) * height
        alpha = 255 if size['mode'] in ('dib24', 'rgb32', 'bitmap') else 128
        assert size['decoded'] == [width, height, 224, 96, 48, alpha, 64, 96, 192, alpha]
        if alpha == 128:
            assert colour == 6
        if size['mode'] == 'both':
            assert 'PNG' in size['formats'] and len(size['formats']) >= 2
        shown = read(f'paste-{index}.messages.json')
        assert shown['chat']['id'] == send['body']['chat'] and shown['chat']['provider'] == size['provider']
        message, = [row for row in shown['messages'] if row['id'] == send['message_id']]
        assert message['from_me'] and message['media_type'] == 'image'
        for phase in ('staged', 'sent'):
            name = f'paste-{index}-{phase}'
            assert (folder / f'{name}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
            assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
            assert read(f'{name}.state.json')['selected']['id'] == send['body']['chat']
        assert f'paste-image paste-{index} PASS' in proof
        assert f'clipboard: paste-{index} {size["mode"]} {width}x{height}' in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: paste-image' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    print('PASTE IMAGE EVIDENCE VERIFIED: screenshot uploads, decoded dimensions, alpha, rows, all providers and isolation')
