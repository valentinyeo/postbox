from pathlib import Path
import json
import runpy
import sys


PNG = runpy.run_path(str(Path(__file__).with_name('check-workspace-icons.py')))


def luminance(rgb):
    channels = [value / 255 for value in rgb]
    channels = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
    return sum(a * b for a, b in zip(channels, (0.2126, 0.7152, 0.0722)))


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)))
    return (lb + 0.05) / (la + 0.05)


def crop(image, rect):
    left, top, right, bottom = rect
    assert 0 <= left < right <= len(image[0]) and 0 <= top < bottom <= len(image), (rect, len(image), len(image[0]))
    return [pixel for row in image[top:bottom] for pixel in row[left:right]]


def ink(image, rect):
    pixels = crop(image, rect)
    background = sorted(pixels, key=luminance)[len(pixels) // 2]
    marked = [pixel for pixel in pixels if contrast(pixel, background) >= 2]
    assert marked, ('no drawn text', rect)
    counts = {}
    for pixel in marked:
        counts[pixel] = counts.get(pixel, 0) + 1
    common = sorted(counts.items(), key=lambda row: row[1], reverse=True)[:4]
    return dict(pixels=len(marked), contrast=round(contrast(max(marked, key=luminance), background), 3), signature=sorted(count for _, count in common))


def check_hub_sync_line(folder):
    folder = Path(folder)
    session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
    assert session['sha256'] and session['commit']
    assert not (folder / 'failure.txt').exists()
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert 'hub-wake-refresh retry-backoff PASS' in proof
    assert 'hub-wake-refresh sync-line PASS' in proof
    evidence = json.loads((folder / 'sync-line.json').read_text(encoding='utf-8-sig'))
    caught_up, offline = evidence['caught_up'], evidence['offline']
    assert caught_up['state'] == 'caught_up' and caught_up['line'].startswith('Up to date'), caught_up
    assert offline['state'] == 'offline' and offline['line'].startswith('Offline'), offline
    assert 'last sync' in offline['line'], offline
    retries = evidence['retries']
    assert retries[:3] == [1000, 2000, 4000], retries
    assert sorted(set(retries)) == sorted(retries), retries
    assert all(later > earlier for earlier, later in zip(retries, retries[1:])), retries
    assert evidence['connected'] == 1, evidence['connected']
    screens = {
        'caught_up': ink(PNG['read_png'](folder / 'sync-caught-up.png')[2], caught_up['rect']),
        'offline': ink(PNG['read_png'](folder / 'sync-offline.png')[2], offline['rect']),
    }
    for name, measured in screens.items():
        assert measured['pixels'] >= 24, (name, measured)
        assert measured['contrast'] >= 2, (name, measured)
    assert screens['caught_up']['signature'] != screens['offline']['signature'], screens
    smaller, larger = sorted((screens['caught_up']['pixels'], screens['offline']['pixels']))
    assert larger - smaller >= max(8, larger // 20), screens
    (folder / 'sync-line-pixels.json').write_text(json.dumps(dict(evidence, screens=screens), indent=2) + '\n', encoding='utf-8')
    print('SYNC LINE VERIFIED: last sync time drawn in the chat header, retries 1/2/4 s then capped, one log line per change')


if __name__ == '__main__':
    check_hub_sync_line(sys.argv[1])
