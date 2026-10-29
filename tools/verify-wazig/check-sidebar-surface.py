from collections import Counter
import argparse
import hashlib
import json
from pathlib import Path
import runpy


PNG = runpy.run_path(str(Path(__file__).with_name('check-workspace-icons.py')))


def luminance(rgb):
    channels = [value / 255 for value in rgb]
    channels = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
    return sum(a * b for a, b in zip(channels, (0.2126, 0.7152, 0.0722)))


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)))
    return (lb + 0.05) / (la + 0.05)


def pixels(image, rect):
    left, top, right, bottom = rect
    assert 0 <= left < right <= len(image[0]) and 0 <= top < bottom <= len(image), rect
    return [pixel for row in image[top:bottom] for pixel in row[left:right]]


def mean(values):
    assert values
    return [sum(pixel[channel] for pixel in values) / len(values) for channel in range(3)]


def ink(image, rect, background):
    counts = Counter(pixel for pixel in pixels(image, rect) if contrast(pixel, background) >= 2)
    assert counts, ('missing list text', rect)
    colour, count = counts.most_common(1)[0]
    return dict(rgb=list(colour), pixels=count, contrast=contrast(colour, background))


def measure_pair(image, before, layout, baseline_layout):
    assert len(image) == len(before) and len(image[0]) == len(before[0]), 'screenshot dimensions changed'
    x, y, right, bottom = layout['client']
    edge = layout['edge']
    lx, ly, lr, lb = layout['list']
    dpi = layout['dpi']
    assert 96 <= dpi <= 192
    px = lambda value: (value * dpi + 48) // 96
    assert x == lx and edge - lr == 8
    assert edge - x == max(px(280), min((right - x) // 3, px(300))), 'approved sidebar width'
    assert ly - y == px(56) and lb == bottom, 'search pill stays above the rows'
    sidebar = mean(pixels(image, [x + px(2), ly + px(130), x + px(7), bottom - px(8)]))
    chat = mean(pixels(image, [edge + 2, y + px(8), edge + px(8), y + px(40)]))
    divider = pixels(image, [edge, y, edge + 1, bottom])
    name_rect = [lx + px(66), ly + px(60 + 10), lr - px(54), ly + px(60 + 34)]
    search_rect = [x + px(20), y + px(15), x + px(24), y + px(40)]
    return dict(theme=layout['theme'], sidebar_rgb=sidebar, chat_rgb=chat, divider=divider,
                name=ink(image, name_rect, sidebar), search_rgb=mean(pixels(image, search_rect)),
                left_edge=pixels(image, [edge - 1, y, edge, bottom]),
                right_edge=pixels(image, [edge + 1, y, edge + 2, bottom]))


def validate(metrics):
    for row in metrics:
        dark = row['theme'] == 'amoled'
        sidebar = (16, 16, 16) if dark else (27, 33, 30)
        chat = (16, 16, 16) if dark else (15, 21, 18)
        divider = (36, 36, 36) if dark else (48, 54, 51)
        search = (31, 31, 31) if dark else (27, 33, 30)
        for field, expected in [('sidebar_rgb', sidebar), ('chat_rgb', chat), ('search_rgb', search)]:
            assert max(abs(a - b) for a, b in zip(row[field], expected)) <= 1, (field, row[field])
        for field, expected in [('divider', divider), ('left_edge', sidebar), ('right_edge', chat)]:
            assert sum(max(abs(a - b) for a, b in zip(pixel, expected)) <= 1 for pixel in row[field]) / len(row[field]) >= 0.995, field
        assert row['name']['pixels'] >= 24 and row['name']['contrast'] >= 4.5, 'readable sidebar name'


def check_sidebar_surface(folder):
    def read(path):
        return json.loads(path.read_text(encoding='utf-8-sig'))

    baseline = folder / 'baseline'
    session, old_session = read(folder / 'session.json'), read(baseline / 'session.json')
    provenance = read(folder / 'sidebar-builds.json')
    assert session['feature'] == old_session['feature'] == 'sidebar-surface'
    assert session['commit'] == provenance['candidate_commit']
    assert old_session['commit'] == provenance['baseline_commit']
    assert session['sha256'] == provenance['candidate_sha256']
    assert old_session['sha256'] == provenance['baseline_sha256']
    assert session['commit'] != old_session['commit']
    assert provenance['assertion_parent'] == provenance['baseline_commit']
    assert provenance['fixture_sha256'] == hashlib.sha256(Path(__file__).parents[2].joinpath('src/verify_text.json').read_bytes()).hexdigest().upper()
    layouts, old_layouts = read(folder / 'sidebar-layout.json'), read(baseline / 'sidebar-layout.json')
    assert [row['theme'] for row in layouts] == [row['theme'] for row in old_layouts] == ['amoled', 'green']
    metrics = []
    for current, old in zip(layouts, old_layouts):
        name = current['screenshot']
        assert name == f"sidebar-{current['theme']}.png"
        image = PNG['read_png'](folder / name)[2]
        before = PNG['read_png'](baseline / name)[2]
        metrics.append(measure_pair(image, before, current, old))
        try:
            validate([measure_pair(before, before, old, old)])
        except AssertionError:
            pass
        else:
            raise AssertionError('Historical sidebar unexpectedly matches the approved design')
        for directory in (folder, baseline):
            state = read(directory / name.replace('.png', '.state.json'))
            assert state['theme'] == current['theme'] and state['selected']['id'] == 'verify-alpha' and state['chat_count'] == 2
            messages = read(directory / name.replace('.png', '.messages.json'))['messages']
            assert len(messages) == 1 and messages[0]['id'] == 'ISSUE-462-PARAGRAPH'
            assert messages[0]['text'].startswith('Clear letters make everyday messages easy to read.')
    (folder / 'sidebar-pixels.json').write_text(json.dumps(metrics, indent=2) + '\n', encoding='utf-8')
    for directory in (folder, baseline):
        assert 'JOURNEY PASSED: sidebar-surface' in (directory / 'result.txt').read_text(encoding='utf-8-sig')
        assert 'CLEANUP PASSED:' in (directory / 'cleanup.txt').read_text(encoding='utf-8-sig')
        assert not (directory / 'failure.txt').exists()
        state = read(directory / 'side-effects.json')
        assert state['sync'] == 'stopped' and state['pending_sends'] == state['pending_archives'] == 0
        assert state['production_preferences_absent'] and state['whatsapp_store_absent'] and state['telegram_store_absent']
    validate(metrics)
    print('SIDEBAR PIXELS VERIFIED: approved graphite geometry, search pill, readable names, one-pixel divider and historical red control')
    return metrics


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    check_sidebar_surface(parser.parse_args().folder)
