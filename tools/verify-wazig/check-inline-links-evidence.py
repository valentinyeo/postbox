import json
import struct
import zlib


def png_rows(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    offset, compressed = 8, bytearray()
    while offset < len(data):
        length = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        chunk = data[offset + 8:offset + 8 + length]
        offset += 12 + length
        if kind == b'IHDR':
            width, height, depth, colour, compression, filtering, interlace = struct.unpack('>IIBBBBB', chunk)
            assert depth == 8 and colour in (2, 6) and compression == filtering == interlace == 0
        elif kind == b'IDAT':
            compressed.extend(chunk)
        elif kind == b'IEND':
            break
    channels = 4 if colour == 6 else 3
    stride = width * channels
    decoded = zlib.decompress(compressed)
    assert len(decoded) == (stride + 1) * height
    previous = bytearray(stride)
    for y in range(height):
        index = y * (stride + 1)
        mode = decoded[index]
        row = bytearray(decoded[index + 1:index + 1 + stride])
        for i in range(stride):
            left = row[i - channels] if i >= channels else 0
            above = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if mode == 1:
                row[i] = (row[i] + left) & 255
            elif mode == 2:
                row[i] = (row[i] + above) & 255
            elif mode == 3:
                row[i] = (row[i] + (left + above) // 2) & 255
            elif mode == 4:
                estimate = left + above - upper_left
                distances = (abs(estimate - left), abs(estimate - above), abs(estimate - upper_left))
                predictor = (left, above, upper_left)[distances.index(min(distances))]
                row[i] = (row[i] + predictor) & 255
            else:
                assert mode == 0
        yield width, height, channels, row
        previous = row


def underline(path, rect):
    left, top, right, bottom = rect
    best = 0
    for y, (width, height, channels, row) in enumerate(png_rows(path)):
        assert 0 <= left < right <= width and 0 <= top < bottom <= height
        if not top <= y < bottom:
            continue
        run = 0
        for x in range(left, right):
            pixel = row[x * channels:x * channels + 3]
            run = run + 1 if min(pixel) >= 170 else 0
            best = max(best, run)
    return best


def check_inline_links(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def inside(point, rect):
        return rect[0] <= point[0] < rect[2] and rect[1] <= point[1] < rect[3]

    session = read('session.json')
    targets = read('inline-targets.json')
    assert session['feature'] == 'inline-links' and session['sha256'] and session['commit']
    assert targets['session'] == session['id'] and targets['app_pid'] == session['pid']
    assert targets['bridge'] == session['bridge_url'] and targets['bridge'].startswith('http://127.0.0.1:')
    stages = read('inline-stages.json')
    by_name = {stage['name']: stage for stage in stages}
    assert len(by_name) == len(stages)
    providers = ['whatsapp', 'slack', 'signal', 'telegram']
    assert set(targets['providers']) == set(providers)
    for provider in providers:
        target = targets['providers'][provider]
        prefix = targets['bridge'] + '/inline-links/' + provider
        assert target['body'] == prefix + '-body-' + 'abcdefghij' * 18
        assert target['quote'] == prefix + '-quote-' + 'klmnopqrst' * 18
        assert target['fallback'] == prefix + '-fallback-' + 'uvwxyzabcd' * 18
        shown = by_name[provider + '-fixture']['messages']
        assert shown['chat']['id'] == target['id'] and shown['chat']['provider'] == provider
        rows = {row['id']: row for row in shown['messages']}
        reply = rows['INLINE-REPLY']
        assert reply['quote'] == target['quote'] and reply['quoted_msg_id'] == 'INLINE-BODY'
        assert reply['quote_fragments']
        for fragment in reply['quote_fragments']:
            units = reply['quote'].encode('utf-16-le')
            token = units[fragment['start'] * 2:fragment['end'] * 2].decode('utf-16-le')
            assert token == target['quote']
            assert fragment['rect'][2] > fragment['rect'][0] and fragment['rect'][3] > fragment['rect'][1]
        assert any(inside(by_name[provider + '-incoming']['point'], f['rect']) for f in reply['quote_fragments'])

    whatsapp = targets['providers']['whatsapp']
    appearance = by_name['appearance']
    for key in ('body_cursor', 'quote_cursor'):
        sample = appearance[key]
        assert sample['cursor'] == sample['hand'] != 0 and sample['flags'] & 1
    assert appearance['plain_cursor']['cursor'] != appearance['plain_cursor']['hand']
    for key in ('body_style', 'quote_style'):
        sample = appearance[key]
        assert underline(folder / sample['screenshot'], sample['pixel_rect']) == sample['longest_bright_run'] >= 8
    rows = {row['id']: row for row in appearance['messages']['messages']}
    body, reply, outgoing, block = (rows[key] for key in ('INLINE-BODY', 'INLINE-REPLY', 'INLINE-OUT', 'INLINE-BLOCK'))
    assert body['links'] == [whatsapp['body']]
    rects = [r for r in body['link_rects'][0] if r[2] > r[0] and r[1] >= 72]
    assert len(rects) >= 2
    assert inside(by_name['body-first']['point'], rects[0])
    assert inside(by_name['body-last']['point'], rects[-1])
    assert outgoing['from_me'] and any(inside(by_name['quote-outgoing']['point'], f['rect']) for f in outgoing['quote_fragments'])
    assert not block['quoted_msg_id'] and len(block['quote_fragments']) >= 2
    assert len({f['rect'][1] for f in block['quote_fragments']}) >= 2
    assert any(inside(by_name['quote-fallback']['point'], f['rect']) for f in block['quote_fragments'])
    for fragment in block['quote_fragments']:
        data = block['quote'].encode('utf-16-le')
        assert data[fragment['start'] * 2:fragment['end'] * 2].decode('utf-16-le') == whatsapp['fallback']
    assert any(inside(by_name['quote-drag']['point'], f['rect']) for f in reply['quote_fragments'])
    assert inside(by_name['quote-jump']['point'], reply['quote_line'])
    assert not any(inside(by_name['quote-jump']['point'], f['rect']) for f in reply['quote_fragments'])
    assert by_name['quote-jump']['status']['reply_jump_count'] == by_name['quote-jump']['jump_before'] + 1
    assert by_name['quote-jump']['status']['reply_jump_id'] == 'INLINE-BODY'
    assert by_name['quote-drag']['status']['reply_jump_count'] == by_name['quote-drag']['jump_before']
    assert by_name['mark']['marked'] and not by_name['unmark']['marked']
    assert by_name['ctrl-o']['palette_count'] == 1
    assert (folder / 'inline-palette.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')

    expected = []
    dispatch = {
        'body-first': whatsapp['body'], 'body-last': whatsapp['body'],
        'quote-outgoing': whatsapp['quote'], 'quote-fallback': whatsapp['fallback'], 'ctrl-o': whatsapp['body'],
        **{provider + '-incoming': targets['providers'][provider]['quote'] for provider in providers},
    }
    last_ack = 0
    for stage in stages:
        if 'ack' in stage:
            assert stage['ack'] == stage['before'] + 1 and stage['ack'] > last_ack
            assert all(abs(stage['ack_point'][i] - stage['end'][i]) <= 1 for i in (0, 1))
            assert stage['status']['pending_sends'] == 0
            last_ack = stage['ack']
        if stage['name'] in dispatch:
            expected.append(dispatch[stage['name']])
        if 'receipts' in stage:
            assert [receipt['url'] for receipt in stage['receipts']] == expected
            for receipt in stage['receipts']:
                assert receipt['pid'] == session['pid'] and receipt['session'] == session['id'] and receipt['result'] > 32
    retained = [json.loads(line) for line in (folder / 'final-data' / 'verification-url-launches.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert [receipt['url'] for receipt in retained] == expected
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert not any(row.get('method') not in ('GET', 'HEAD', 'SSE') and not (row.get('method') == 'POST' and row.get('wire_path') == '/v1/wazig/mark-read' and row.get('status') == 200) for row in requests)
    assert read('result.json') == {'feature': 'inline-links', 'status': 'passed'}
    assert not (folder / 'failure.txt').exists()
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: native input acknowledgments and OS-accepted URL dispatch; page load not asserted')
