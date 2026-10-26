import copy
from pathlib import Path
import runpy
import tempfile


ORACLE = runpy.run_path(str(Path(__file__).with_name('check-sidebar-surface.py')))
LAYOUT = dict(theme='amoled', dpi=96, screenshot='sidebar-amoled.png', client=[0, 0, 840, 300], edge=280, list=[0, 0, 272, 300])
PALETTES = {
    'amoled': ((0, 0, 0), (0, 0, 0), (18, 18, 18), (36, 36, 36), (255, 255, 255), (204, 204, 204)),
    'green': ((15, 21, 18), (23, 29, 26), (27, 33, 30), (48, 54, 51), (222, 228, 223), (191, 201, 195)),
    'light-control': ((255, 255, 255), (255, 255, 255), (239, 239, 239), (235, 235, 235), (16, 16, 16), (60, 60, 60)),
}


def fill(image, rect, colour):
    x, y, right, bottom = rect
    for row in image[y:bottom]:
        row[x:right] = [colour] * (right - x)


def fixture(palette, changed):
    chat, old_sidebar, new_sidebar, divider, name, kind = palette
    image = [[chat] * 840 for _ in range(300)]
    fill(image, [0, 0, 280, 300], new_sidebar if changed else old_sidebar)
    if changed:
        fill(image, [280, 0, 281, 300], divider)
    fill(image, [70, 76, 130, 88], name)
    fill(image, [70, 100, 100, 110], kind)
    fill(image, [340, 80, 480, 150], (40, 50, 45))
    return image


def measure(image, before, theme='amoled'):
    layout = dict(LAYOUT, theme=theme, screenshot=f'sidebar-{theme}.png')
    return ORACLE['measure_pair'](image, before, layout, layout)


def reject(image, before, reason):
    try:
        ORACLE['validate']([measure(image, before)])
    except AssertionError:
        return
    raise AssertionError('accepted negative control: ' + reason)


with tempfile.TemporaryDirectory() as directory:
    for theme, palette in PALETTES.items():
        before, after = fixture(palette, False), fixture(palette, True)
        for label, image in [('before', before), ('after', after)]:
            path = Path(directory) / f'{theme}-{label}.png'
            ORACLE['PNG']['write_png'](path, image)
            decoded = ORACLE['PNG']['read_png'](path)[2]
            assert decoded == image
            if label == 'before':
                before = decoded
            else:
                after = decoded
        result = measure(after, before, theme)
        ORACLE['validate']([result])
        print(theme, {key: result[key] for key in ['sidebar_rgb', 'chat_rgb', 'surface_contrast', 'divider_sidebar_delta', 'divider_chat_delta']},
              'text contrasts', {key: value['after']['contrast'] for key, value in result['text'].items()})
    before, after = fixture(PALETTES['amoled'], False), fixture(PALETTES['amoled'], True)
    reject(before, before, 'old main pixels: black sidebar and absent divider')
    controls = [
        ('missing divider', [280, 0, 281, 300], (0, 0, 0)),
        ('two-pixel divider', [279, 0, 280, 300], (36, 36, 36)),
        ('shadow band', [281, 0, 284, 300], (36, 36, 36)),
        ('heavy divider', [280, 0, 281, 300], (120, 120, 120)),
        ('sidebar still black', [0, 184, 264, 292], (0, 0, 0)),
        ('row surface still black', [2, 112, 8, 176], (0, 0, 0)),
        ('low contrast list name', [70, 76, 130, 88], (60, 60, 60)),
        ('low contrast secondary text', [70, 100, 100, 110], (60, 60, 60)),
        ('text colour changed', [70, 76, 130, 88], (240, 240, 240)),
        ('one changed chat channel', [500, 200, 501, 201], (0, 0, 1)),
        ('changed message bubble', [340, 80, 341, 81], (41, 50, 45)),
        ('blank screenshot', [0, 0, 840, 300], (0, 0, 0)),
        ('interrupted divider', [280, 100, 281, 110], (0, 0, 0)),
    ]
    for reason, rect, colour in controls:
        damaged = copy.deepcopy(after)
        fill(damaged, rect, colour)
        reject(damaged, before, reason)
    wrong_layout = copy.deepcopy(LAYOUT)
    wrong_layout['list'][1] += 1
    try:
        ORACLE['measure_pair'](after, before, LAYOUT, wrong_layout)
    except AssertionError:
        pass
    else:
        raise AssertionError('accepted changed layout')
print('SIDEBAR VALIDATOR CONTROLS PASSED')
