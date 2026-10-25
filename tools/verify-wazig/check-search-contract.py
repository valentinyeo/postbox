import argparse
import ast
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import runpy


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
API = runpy.run_path(str(HERE / 'check-search-evidence.py'))


def queries():
    fixture = json.loads((HERE / 'search-queries.json').read_text())
    cases = fixture['queries']
    assert len(cases) >= 20 and len({case['query'] for case in cases}) == len(cases)
    assert {'thread', 'message', 'contact', 'account', 'archived', 'command', 'empty-list', 'no-match'} <= {case['category'] for case in cases}
    assert all(case['query'] and len(case['query']) < 64 for case in cases)
    assert any(case['query'] == 'archive' for case in cases)
    for case in cases:
        query = case['query'].lower()
        if case['category'] == 'message':
            assert query in fixture['message'].lower()
        elif case['category'] not in ('empty-list', 'no-match'):
            assert any(query in row['name'].lower() or query in row['jid'].lower() for row in fixture['rows']), case
    assert len({row['jid'] for row in fixture['rows']}) == len(fixture['rows'])
    for path in HERE.glob('*.py'):
        if path.name.startswith('check-search-') or path.name == 'search-fixture.py':
            ast.parse(path.read_text(), filename=str(path))
    recorder = (HERE / 'search-proof.ps1').read_text()
    journey = (HERE / 'journey-search.ps1').read_text()
    assert "@('^f', '/')" in journey and 'search-queries.json' in journey
    assert journey.index("'search-parity.json'") < journey.index('baseline parity was captured')
    assert 'Read-ListLabels $list' in recorder and 'Read-Control $Session chats' in recorder
    assert 'HasKeyboardFocus' in recorder and "'1064'" in recorder
    print(f'SEARCH QUERIES VERIFIED: {len(cases)} shared cases')


def rejected(function, *args):
    try:
        function(*args)
    except AssertionError:
        return
    raise AssertionError(f'negative control accepted by {function.__name__}')


def sample(query='archive', fixed=True):
    rows = [dict(provider='whatsapp', account='fixture', id=f'chat-{index}', name=f'archive chat {index}', archived=False) for index in range(2)]
    return dict(query=query, focused=True, palette=fixed, edit_id='1064' if fixed else '1008', rows=rows,
                identities=[f"whatsapp|fixture|chat-{index}" for index in range(2)],
                labels=[row['name'] for row in rows] + (['Archive selected chat'] if fixed else []), native_count=3 if fixed else 2,
                shortcut='^f', state=dict(search=query, chat_count=2, pending_sends=0, pending_archives=0,
                                         show_archived=False, unread_only=False, include_archived=False, current_view=dict(inbox=True)))


def controls():
    good = sample()
    API['check_sample'](good, 'archive', True)
    API['check_sample'](sample(fixed=False), 'archive', False)
    for field, value in [('labels', list(reversed(good['labels']))), ('identities', list(reversed(good['identities']))),
                         ('identities', good['identities'][:1]), ('focused', False), ('palette', False), ('edit_id', '1008'), ('query', 'wrong')]:
        bad = deepcopy(good)
        bad[field] = value
        rejected(API['check_sample'], bad, 'archive', True)
    fixture = dict(schema=1, rows=[dict(jid=row['id'], name=row['name'], archived=False) for row in good['rows']], queries=[dict(query='archive', category='command')])
    second = deepcopy(good)
    second['shortcut'] = '/'
    proof = dict(schema=1, baseline=False, commit='fixture-a', sha256='fixture-build', records=[dict(case=fixture['queries'][0], empty_start=False, samples=[good, second])])
    API['check_parity'](proof, fixture, True)
    bad = deepcopy(proof)
    changed = bad['records'][0]['samples'][1]
    changed['rows'].reverse()
    changed['identities'].reverse()
    changed['labels'][:2] = reversed(changed['labels'][:2])
    rejected(API['check_parity'], bad, fixture, True)
    removal = dict(controls=0, native=False, labels=[], list_top=0, client_top=0)
    API['check_removal'](removal)
    for field, value in [('controls', 1), ('native', True), ('labels', ['Search All Ctrl+F']), ('list_top', 48)]:
        bad = dict(removal, **{field: value})
        rejected(API['check_removal'], bad)
    ink_sample = sample('Verification')
    ink_sample['rows'][0].update(name='Verification Alpha')
    ink_sample['rows'][1].update(name='Verification Archived Atlas', archived=True)
    ink_sample['labels'] = ['Verification Alpha', 'Verification Archived Atlas  ·  Archived']
    ink_sample['native_count'] = 2
    layout = dict(sample=ink_sample, x=0, y=0, row_height=40, height=80)
    image = [[(0, 0, 0)] * 220 for _ in range(80)]
    for y in range(8, 28):
        image[y][30:70] = [(240, 240, 240)] * 40
        image[y + 40][30:70] = [(140, 140, 140)] * 40
    API['check_ink'](image, layout)
    bad_image = deepcopy(image)
    for y in range(48, 68):
        bad_image[y][30:70] = [(240, 240, 240)] * 40
    rejected(API['check_ink'], bad_image, layout)
    for path in ('check-search-evidence.py', 'search-proof.ps1', 'journey-search.ps1'):
        assert not any(line.lstrip().startswith(('#', '//')) for line in (HERE / path).read_text().splitlines()), path
    print('SEARCH NEGATIVE CONTROLS VERIFIED: order, set, focus, palette, query, bar, slot, groups and ink')


def source():
    text = (ROOT / 'src/main.zig').read_text()
    for removed in ('id_search', 'a.search)', 'a.search,', 'a.search.?', 'search_pill', 'search_height', 'updateSearchCue', 'Search All'):
        assert removed not in text, removed
    assert 'fn openSearchPalette(a: *App) void' in text
    assert 'command_search => openSearchPalette(a)' in text
    for start, end in [("if (control and key == 'F')", "if (control and !alt and !shift and key == 'A')"),
                       ('if (key == win.VK_OEM_2)', "if (key == 'E')")]:
        assert 'openSearchPalette(a)' in text.split(start, 1)[1].split(end, 1)[0]
    assert 'if (control and key == \'K\') {\n        openPalette(a);' in text
    apply = text.split('fn applyChats(', 1)[1].split('fn ', 1)[0]
    assert 'a.search_query.slice()' in apply and 'controlSortChats(a, a.chats[0..a.chat_count], view)' in apply
    filtering = text.split('fn paletteFilter(', 1)[1].split('fn paletteMove(', 1)[0]
    assert 'a.palette_search_mode' in filtering and 'refilterChats(a)' in filtering and 'appendPaletteChat(a, index)' in filtering
    assert 'paletteScore(' in filtering and 'appendPalettePeople(' in filtering
    draw = text.split('fn drawPaletteItem(', 1)[1].split('fn paletteProc(', 1)[0]
    assert 'theme.archivedRowColor' in draw and 'palette_item.archived' in draw
    assert '"Chats"' in draw and '"Commands"' in draw
    assert 'win.MoveWindow(hwnd, 0, header_height, left_width - scrollbar_width, list_bottom - header_height' in text
    print('SEARCH SOURCE VERIFIED: removed control and slot, shared exact filter, unchanged Ctrl+K dispatch, groups and dim ink')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--queries', action='store_true')
    parser.add_argument('--controls', action='store_true')
    parser.add_argument('--source', action='store_true')
    args = parser.parse_args()
    assert args.queries or args.controls or args.source
    if args.queries:
        queries()
    if args.controls:
        controls()
    if args.source:
        source()
