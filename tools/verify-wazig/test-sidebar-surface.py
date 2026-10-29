import copy
from pathlib import Path
import runpy
import tempfile


ORACLE = runpy.run_path(str(Path(__file__).with_name('check-sidebar-surface.py')))
LAYOUT = dict(theme='amoled', dpi=96, screenshot='sidebar-amoled.png', client=[0, 0, 960, 320], edge=300, list=[0, 56, 292, 320], composer=[330, 260, 800, 310])
PALETTES = {
    'amoled': ((16, 16, 16), (16, 16, 16), (36, 36, 36), (31, 31, 31), (242, 242, 242)),
    'green': ((15, 21, 18), (27, 33, 30), (48, 54, 51), (27, 33, 30), (222, 228, 223)),
}


def fill(image, rect, colour):
    x, y, right, bottom = rect
    for row in image[y:bottom]:
        row[x:right] = [colour] * (right - x)


def fixture(palette):
    chat, sidebar, divider, search, name = palette
    image = [[chat] * 960 for _ in range(320)]
    fill(image, [0, 0, 300, 320], sidebar)
    fill(image, [300, 0, 301, 320], divider)
    fill(image, [12, 10, 288, 46], search)
    fill(image, [70, 128, 132, 140], name)
    return image


def measure(image, theme='amoled', layout=LAYOUT):
    layout = dict(layout, theme=theme)
    return ORACLE['measure_pair'](image, image, layout, layout)


def reject(image, reason, layout=LAYOUT):
    try:
        ORACLE['validate']([measure(image, layout=layout)])
    except AssertionError:
        return
    raise AssertionError('accepted negative control: ' + reason)


with tempfile.TemporaryDirectory() as directory:
    for theme, palette in PALETTES.items():
        image = fixture(palette)
        path = Path(directory) / f'{theme}.png'
        ORACLE['PNG']['write_png'](path, image)
        decoded = ORACLE['PNG']['read_png'](path)[2]
        assert decoded == image
        ORACLE['validate']([measure(decoded, theme)])
    after = fixture(PALETTES['amoled'])
    controls = [
        ('missing divider', [300, 0, 301, 320], (16, 16, 16)),
        ('two-pixel divider', [299, 0, 300, 320], (36, 36, 36)),
        ('shadow band', [301, 0, 303, 320], (36, 36, 36)),
        ('heavy divider', [300, 0, 301, 320], (120, 120, 120)),
        ('old black sidebar', [0, 186, 8, 312], (0, 0, 0)),
        ('missing search pill', [12, 10, 288, 46], (16, 16, 16)),
        ('unreadable name', [70, 128, 132, 140], (60, 60, 60)),
        ('blank screenshot', [0, 0, 960, 320], (0, 0, 0)),
        ('interrupted divider', [300, 100, 301, 110], (16, 16, 16)),
    ]
    for reason, rect, colour in controls:
        damaged = copy.deepcopy(after)
        fill(damaged, rect, colour)
        reject(damaged, reason)
    old_layout = dict(LAYOUT, edge=280, list=[0, 0, 272, 320])
    reject(after, 'historical sidebar geometry', old_layout)
print('SIDEBAR VALIDATOR CONTROLS PASSED')
