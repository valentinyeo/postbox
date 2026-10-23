import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path
import sys


spec = importlib.util.spec_from_file_location('workspace_icons', Path(__file__).with_name('check-workspace-icons.py'))
workspace_icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workspace_icons)
read_png = workspace_icons.read_png


def offsets(rows, pill, edit):
    left, top, right, bottom = pill
    assert 0 <= left < right <= len(rows[0]) and 0 <= top < bottom <= len(rows), 'invalid pill bounds'
    x0, _, x1, _ = edit
    assert left < x0 < x1 < right, 'invalid edit bounds'
    pixels = [(x, y, rows[y][x]) for y in range(top + 2, bottom - 2) for x in range(x0, x1)]
    fill = Counter(pixel for _, _, pixel in pixels).most_common(1)[0][0]
    ink = {(x, y) for x, y, pixel in pixels if max(abs(a - b) for a, b in zip(pixel, fill)) >= 48}
    caret_columns = []
    for x in range(x0, x1):
        run = longest = 0
        for y in range(top + 2, bottom - 2):
            run = run + 1 if (x, y) in ink else 0
            longest = max(longest, run)
        if longest >= (bottom - top) * 0.45:
            caret_columns.append(x)
    groups = []
    for x in caret_columns:
        if not groups or x != groups[-1][-1] + 1:
            groups.append([])
        groups[-1].append(x)
    caret = {x for group in groups if len(group) <= 2 for x in group}
    ink = {(x, y) for x, y in ink if x not in caret}
    assert len(ink) >= 12, 'missing text ink'
    xs, ys = zip(*ink)
    return {'dx': (min(xs) + max(xs) + 1 - left - right) / 2,
            'dy': (min(ys) + max(ys) + 1 - top - bottom) / 2}


def check(folder):
    layout = json.loads((folder / 'search-center-layout.json').read_text(encoding='utf-8-sig'))
    result = {}
    for state in ('placeholder', 'typed'):
        entry = layout[state]
        width, height, rows = read_png(folder / f'search-center-{state}.png')
        assert entry['pill'] == [0, 0, width, height], 'crop and pill disagree'
        assert entry['focused'] == (state == 'typed'), 'wrong focus state'
        assert entry['text'] == ('Beta' if state == 'typed' else ''), 'wrong search text'
        result[state] = offsets(rows, entry['pill'], entry['edit'])
    (folder / 'search-center.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    failures = [f'{state} dx={value["dx"]} dy={value["dy"]}' for state, value in result.items()
                if abs(value['dx']) > 2 or abs(value['dy']) > 1]
    if failures:
        raise ValueError('; '.join(failures))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    try:
        check(args.folder)
    except (AssertionError, ValueError, OSError, KeyError) as error:
        print(f'search-center FAIL {error}', file=sys.stderr)
        sys.exit(1)
    print('search-center PASS placeholder and typed ink within 2px horizontal and 1px vertical')
