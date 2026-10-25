import argparse
from collections import Counter
import json
from pathlib import Path
import runpy


read_png = runpy.run_path(str(Path(__file__).with_name('check-workspace-icons.py')))['read_png']


def read(folder, name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))


def luminance(colour):
    def linear(value):
        value /= 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
    return sum(weight * linear(value) for weight, value in zip((0.2126, 0.7152, 0.0722), colour))


def contrast(first, second):
    a, b = luminance(first), luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def measure(image, rect):
    left, top, right, bottom = rect
    assert 0 <= left < right <= len(image[0]) and 0 <= top < bottom <= len(image), rect
    pixels = [pixel for row in image[top:bottom] for pixel in row[left:right]]
    background = Counter(pixels).most_common(1)[0][0]
    ranked = sorted(pixels, key=lambda pixel: contrast(pixel, background), reverse=True)
    text = ranked[23]
    assert sum(contrast(pixel, background) > 1.5 for pixel in pixels) >= 24, 'missing row text'
    return dict(text=list(text), background=list(background), contrast=contrast(text, background), rect=rect)


def check_scene(folder, name, capture=False):
    layout = read(folder, f'{name}.layout.json')
    state = read(folder, f'{name}.state.json')
    rows = read(folder, f'{name}.chats.json')['chats']
    assert rows == layout['rows'] and state['selected']['id'] == layout['selected'], name
    assert state['include_archived'] and not state['show_archived'], name
    assert (state['search'] == 'row') == ('-search-' in name), name
    assert state['current_view']['inbox'] == ('-inbox-' in name), name
    assert layout['mode'] == name.rsplit('-', 1)[1], name
    assert 96 <= layout['dpi'] <= 192 and layout['top'] == 0, name
    scale = layout['dpi'] / 96
    px = lambda value: int(value * scale + 0.5)
    assert layout['row_height'] == px(64), name
    _, _, image = read_png(folder / f'{name}.png')
    archived = next(row for row in rows if row['archived'])
    live = next(row for row in rows if not row['archived'] and row['id'] != layout['selected'])

    def row_measure(row):
        index = rows.index(row)
        assert (index + 1) * layout['row_height'] <= layout['height'], name
        x = layout['x'] + px(66)
        y = layout['y'] + index * layout['row_height'] + px(10)
        return measure(image, [x, y, x + px(125), y + px(24)])

    normal, marked = row_measure(live), row_measure(archived)
    ratio = (marked['contrast'] - 1) / (normal['contrast'] - 1)
    colour_distance = max(abs(a - b) for a, b in zip(normal['text'], marked['text']))
    assert normal['contrast'] >= 4.5, (name, normal)
    if layout['mode'] == 'dim':
        assert layout['selected'] != archived['id'], name
        assert 0.2 < ratio < 0.85, (name, 'archived/live contrast-excess ratio', ratio)
        assert colour_distance > 15, (name, 'archived text is not dimmer')
    else:
        assert colour_distance <= 8, (name, 'archived text not at full strength', normal, marked)
        assert marked['contrast'] >= 4.5, (name, marked)
        if layout['mode'] == 'selected':
            assert layout['selected'] == archived['id'] and state['selected']['archived'], name
        else:
            assert layout['selected'] != archived['id'], name
    metrics = dict(live=normal, archived=marked, dim_ratio=ratio, full_strength_colour_distance=colour_distance,
                   polarity='light' if luminance(normal['background']) > 0.5 else 'dark')
    output = folder / f'{name}.contrast.json'
    if capture:
        output.write_text(json.dumps(metrics, indent=2), encoding='utf-8')
    else:
        assert read(folder, output.name) == metrics, name
    print(f'{name}: {metrics["polarity"]} live={normal["contrast"]:.6f} archived={marked["contrast"]:.6f} dim_ratio={ratio:.6f} text_delta={colour_distance}')
    return metrics


def check_presentation(folder):
    for scope in ('sidebar', 'inbox', 'search'):
        for mode in ('dim', 'hover', 'selected'):
            check_scene(folder, f'archive-{scope}-{mode}')
    for name, enabled, activated in [('archive-palette-on', True, True), ('archive-palette-off', False, True),
                                      ('archive-palette-restored', True, False), ('palette-switch', True, True)]:
        palette = read(folder, f'{name}.palette.json')
        expected = 'Toggle archived chats in this view: ' + ('On' if enabled else 'Off')
        assert palette['query'] == 'archive' and palette['enabled'] == enabled and palette['activated'] == activated, name
        assert palette['expected'] == expected and palette['labels'].count(expected) == 1, name
        assert 0 <= palette['index'] < 10 and palette['labels'][palette['index']] == expected, name
        assert read(folder, f'{name}.state.json')['include_archived'] == enabled, name
        assert (folder / f'{name}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), name
    identities = read(folder, 'archive-identities.json')
    assert identities['before'] == identities['after'] and len(identities['before']) == 4
    assert len(set(identities['before'])) == 4 and sum(row.endswith('|True') for row in identities['before']) == 2
    footer = read(folder, 'archive-footer.json')
    for key in ('include_archived', 'selected', 'chat_count', 'pending_archives', 'current_view', 'search'):
        assert footer['before'][key] == footer['after'][key], key
    assert footer['after']['include_archived'] and footer['after']['pending_archives'] == 0
    assert read(folder, 'archive-footer.state.json') == footer['after']
    assert read(folder, 'archive-footer.chats.json')['chats'] == footer['rows']
    tree = (folder / 'archive-footer.uia.txt').read_text(encoding='utf-8-sig')
    assert '1016 | ListBox |' in tree and '1008 | RICHEDIT50W |' in tree
    assert '1146 |' not in tree and 'Show archived:' not in tree
    _, _, image = read_png(folder / 'archive-footer.png')
    left, top, right, bottom = footer['rect']
    assert 0 <= left < right <= len(image[0]) and 0 <= top < bottom <= len(image)
    pixels = [pixel for row in image[top:bottom] for pixel in row[left:right]]
    assert Counter(pixels).most_common(1)[0][1] / len(pixels) > 0.995, 'former archive label still drawn'
    print('ARCHIVE PRESENTATION VERIFIED: absent inert footer, stateful palette and measured dim/full rows')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--scene')
    parser.add_argument('--both', action='store_true')
    args = parser.parse_args()
    if args.scene:
        check_scene(args.folder, args.scene, capture=True)
    else:
        check_presentation(args.folder)

    if args.both:
        light = args.folder / 'light'
        check_presentation(light)
        palette = read(light, 'fixture-palette.json')
        assert palette['kind'] == 'inverted AMOLED fixture palette' and palette['production_rendering']
        import re
        original = re.findall(r'hex\(0x([0-9a-f]{6})\)', palette['original'])
        inverted = re.findall(r'hex\(0x([0-9a-f]{6})\)', palette['light'])
        assert len(original) == len(inverted) == 16
        assert all(int(a, 16) + int(b, 16) == 0xffffff for a, b in zip(original, inverted))
        for folder, polarity in [(args.folder, 'dark'), (light, 'light')]:
            assert read(folder, 'session.json')['sha256'] != read(light if folder == args.folder else args.folder, 'session.json')['sha256']
            for scope in ('sidebar', 'inbox', 'search'):
                for mode in ('dim', 'hover', 'selected'):
                    assert read(folder, f'archive-{scope}-{mode}.contrast.json')['polarity'] == polarity
        print('ARCHIVE LIGHT AND DARK VERIFIED: screenshot contrast and dim ratios retained for both polarities')
