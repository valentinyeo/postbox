import json


def check_evidence(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'ctrl-badges' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='ctrl-badges', status='passed')
    assert not (folder / 'failure.txt').exists()
    proof = read('ctrl-badges.json')
    assert proof['schema'] == 1 and len(proof['rows']) == 6
    assert proof['idle']['held'] is False and proof['idle']['badges'] in ([], None)
    for stage in ('held', 'jumped'):
        assert proof[stage]['held'] is True, stage
        assert [badge['number'] for badge in proof[stage]['badges']] == [1, 2, 3, 4, 5, 6], stage
    assert proof['released']['held'] is False and proof['released']['badges'] in ([], None)
    rects = [badge['rect'] for badge in proof['held']['badges']]
    tops = [rect[1] for rect in rects]
    assert tops == sorted(tops) and len(set(tops)) == 6
    assert len({rect[0] for rect in rects}) == 1
    assert len(proof['measures']) == 6
    for item in proof['measures']:
        held, after = item['held'], item['after']
        assert held['changed'] * 2 >= held['area'], ('BADGE_PIXELS_MISSING', item['number'])
        assert held['fill_pixels'] * 2 >= held['area'], ('BADGE_FILL_MISSING', item['number'])
        assert held['ink_pixels'] >= 6, ('BADGE_DIGIT_MISSING', item['number'])
        assert after['changed'] * 50 <= after['area'], ('BADGE_STAYS_AFTER_RELEASE', item['number'])
    for name in ('ctrl-before', 'ctrl-held', 'ctrl-jump', 'ctrl-after'):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert actions.count('SendInput: ctrl down') == 1 and actions.count('SendInput: ctrl up') == 1
    assert actions.count('SendInput: digit 3') == 1
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert 'JOURNEY PASSED: ctrl-badges' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('CTRL BADGES EVIDENCE VERIFIED: numbers 1 to 6 while Ctrl is held, kept through Ctrl+3, gone after release')
