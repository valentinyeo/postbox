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
    assert layout == baseline_layout, 'sidebar or chat geometry changed'
    assert len(image) == len(before) and len(image[0]) == len(before[0]), 'screenshot dimensions changed'
    x, y, right, bottom = layout['client']
    edge = layout['edge']
    lx, ly, lr, lb = layout['list']
    dpi = layout['dpi']
    assert 96 <= dpi <= 192

    def px(value):
        return (value * dpi + 48) // 96

    assert x == lx and y == ly and edge - lr == 8
    assert edge - x == max(px(280), min((right - x) // 3, px(390)))
    assert lb == bottom and bottom - ly >= px(192)
    sidebar_rect = [x + px(8), ly + px(136), edge - px(16), bottom - px(8)]
    chat_rect = [edge + 2, y + px(8), edge + px(8), y + px(40)]
    sidebar = mean(pixels(image, sidebar_rect))
    chat = mean(pixels(image, chat_rect))
    row_surface = mean(pixels(image, [x + px(2), ly + px(64), x + px(8), ly + px(128)]))
    old_sidebar = mean(pixels(before, sidebar_rect))
    old_row_surface = mean(pixels(before, [x + px(2), ly + px(64), x + px(8), ly + px(128)]))
    old_chat = mean(pixels(before, chat_rect))
    divider = mean(pixels(image, [edge, y, edge + 1, bottom]))
    lines = []
    for column, expected in [(edge - 1, sidebar), (edge, divider), (edge + 1, chat)]:
        line = pixels(image, [column, y, column + 1, bottom])
        lines.append(sum(max(abs(a - b) for a, b in zip(pixel, expected)) <= 1 for pixel in line) / len(line))
    text = {}
    for label, top, end in [('name', 10, 34), ('kind', 35, 56)]:
        rect = [lx + px(66), ly + px(64 + top), lr - px(54), ly + px(64 + end)]
        text[label] = dict(rect=rect, after=ink(image, rect, sidebar), before=ink(before, rect, old_row_surface))
    cl, ct, cr, cb = layout['composer']
    differences = []
    for row in range(y, bottom):
        for column in range(edge + 1, right):
            if cl <= column < cr and ct <= row < cb:
                continue
            differences.append(max(abs(a - b) for a, b in zip(image[row][column], before[row][column])))
    return dict(theme=layout['theme'], sidebar_rgb=sidebar, row_surface_rgb=row_surface, chat_rgb=chat, baseline_sidebar_rgb=old_sidebar,
                baseline_row_surface_rgb=old_row_surface, baseline_chat_rgb=old_chat, surface_contrast=contrast(sidebar, chat),
                surface_luminance_delta=luminance(sidebar) - luminance(chat), divider_rgb=divider,
                divider_sidebar_delta=abs(luminance(divider) - luminance(sidebar)),
                divider_chat_delta=abs(luminance(divider) - luminance(chat)),
                edge_column_uniform_fractions=lines, text=text, chat_pixels=len(differences),
                chat_max_channel_delta=max(differences), chat_changed_pixels=sum(value != 0 for value in differences),
                sidebar_rect=sidebar_rect, chat_background_rect=chat_rect)


def validate(metrics):
    for row in metrics:
        sidebar, chat = row['sidebar_rgb'], row['chat_rgb']
        assert max(abs(a - b) for a, b in zip(sidebar, row['row_surface_rgb'])) <= 1, ('row surface differs from sidebar', row)
        delta = row['surface_luminance_delta']
        if luminance(chat) < 0.5:
            assert delta > 0.004, ('sidebar not lifted above dark chat', row)
        else:
            assert delta < -0.004, ('light sidebar not darker than chat', row)
        assert 1.08 <= row['surface_contrast'] <= 1.6, ('surface separation', row)
        assert 8 <= sum(abs(a - b) for a, b in zip(sidebar, chat)) / 3 <= 40, ('surface not subtle grey', row)
        assert max(sidebar) - min(sidebar) <= 16, ('sidebar lost theme neutrality', row)
        assert 0.005 <= row['divider_sidebar_delta'] <= 0.04, ('missing or heavy divider', row)
        assert 0.009 <= row['divider_chat_delta'] <= (0.06 if luminance(chat) < 0.5 else 0.22), ('divider invisible against chat', row)
        assert min(row['edge_column_uniform_fractions']) >= 0.995, ('divider not exactly one physical pixel', row)
        for label, text in row['text'].items():
            assert text['after']['pixels'] >= (24 if label == 'name' else 12), ('missing text ink', row)
            assert text['after']['contrast'] >= 4.5, ('list text contrast', row)
            assert text['after']['contrast'] >= text['before']['contrast'] * 0.85, ('list text readability regressed', row)
            assert max(abs(a - b) for a, b in zip(text['after']['rgb'], text['before']['rgb'])) <= 1, ('text colour changed', row)
        assert row['chat_pixels'] > 0 and row['chat_max_channel_delta'] == row['chat_changed_pixels'] == 0, ('chat changed; tolerance is zero', row)


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
    print('SIDEBAR PIXELS VERIFIED: subtle surfaces, readable unchanged text, one-pixel divider, zero changed chat pixels')
    return metrics


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    check_sidebar_surface(parser.parse_args().folder)
