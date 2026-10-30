from pathlib import Path
import hashlib
import json
import re
import sys
import zipfile


def read(folder, name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))


def check(baseline, candidate):
    old = read(baseline, 'session.json')
    new = read(candidate, 'session.json')
    capture = read(baseline, 'font-baseline.json')
    package = read(baseline, 'published-font-package.json')
    release = read(baseline, 'published-font-release.json')
    old_result = read(baseline, 'result.json')
    side_effects = read(baseline, 'side-effects.json')
    new_result = read(candidate, 'result.json')
    fresh = read(candidate, 'text-fresh-default.state.json')
    scale = read(candidate, 'text-scale.json')
    viewport = read(candidate, 'font-viewport.json')
    presets = read(candidate, 'text-presets.json')
    old_state = read(baseline, 'font-baseline.state.json')
    assert package['tag'] == 'v0.9.224'
    assert package['asset_name'] == 'Postbox-v0.9.224.zip'
    digest = package['package_sha256'].lower()
    assert re.fullmatch(r'[0-9a-f]{64}', digest)
    assert package['asset_digest'] == 'sha256:' + digest
    assets = [asset for asset in release['assets'] if asset['name'] == package['asset_name']]
    assert release['tag_name'] == package['tag'] and len(assets) == 1
    assert assets[0]['digest'] == package['asset_digest']
    archive = baseline / package['asset_name']
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == digest
    lines = (baseline / 'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines()
    matches = [line for line in lines if re.fullmatch(r'[0-9a-fA-F]{64} [ *]Postbox-v0\.9\.224\.zip', line)]
    assert len(matches) == 1 and matches[0][:64].lower() == digest
    with zipfile.ZipFile(archive) as data:
        assert data.namelist().count('Messages.exe') == 1
        executable = hashlib.sha256(data.read('Messages.exe')).hexdigest()
    assert executable == old['sha256'].lower() == capture['exe_sha256'].lower()
    assert old['feature'] == 'appearance' and old['expected_version'] == '0.9.224'
    assert old['expected_product'] == 'Postbox' and capture['runtime_version'] == '0.9.224'
    assert old_state['version'] == capture['runtime_version']
    assert old_result['status'] == 'baseline-captured' and old_result['feature'] == 'appearance'
    assert side_effects['production_preferences_absent'] and side_effects['whatsapp_store_absent'] and side_effects['telegram_store_absent']
    assert side_effects['pending_sends'] == side_effects['pending_archives'] == 0 and side_effects['sync'] == 'stopped'
    assert (baseline / 'result.txt').read_text(encoding='utf-8-sig').strip() == 'FONT BASELINE CAPTURED: v0.9.224'
    assert new_result['status'] == 'passed' and new_result['feature'] == 'appearance'
    assert new['feature'] == 'appearance' and re.fullmatch(r'[0-9a-fA-F]{64}', new['sha256']) and new['commit']
    assert new['sha256'].lower() != executable
    assert capture['id'] == old['id'] and capture['root'] == old['root']
    assert capture['pid'] == old['pid'] and capture['start_ticks'] == old['startTicks']
    assert old['id'] != new['id'] and old['root'] != new['root']
    assert capture['initial_saved'] is False and capture['scale'] == 82
    assert scale['initial_saved'] is False and fresh['font_layout']['scale'] == 100
    assert fresh['version'] == new['expected_version']
    assert len(presets) == 4 and presets[1]['scale'] == 100 and presets[1]['points'] == scale['baseline_points']
    assert 0 < capture['points'] < scale['baseline_points']
    assert capture['dpi'] > 0 and abs(capture['points'] - ((15 * 82 * capture['dpi'] + 4800) // 9600) * 72 / capture['dpi']) < 0.1
    assert (capture['width'], capture['height']) == (1920, 1032)
    assert (viewport['width'], viewport['height'], viewport['hosted_only']) == (1920, 1032, True)
    assert viewport['dpi'] == capture['dpi']
    for folder, name in ((baseline, 'font-baseline'), (candidate, 'text-fresh-default')):
        image = (folder / (name + '.png')).read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        version = capture['runtime_version'] if folder == baseline else new['expected_version']
        title = (folder / (name + '.uia.txt')).read_text(encoding='utf-8-sig').splitlines()[0]
        assert re.fullmatch(rf'MessagesZig \| (?:.+ - )?Postbox v{re.escape(version)}', title)
        assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
        assert not (folder / 'failure.txt').exists()
    (candidate / 'font-comparison.json').write_text(json.dumps({'baseline_tag': package['tag'], 'package_sha256': digest, 'baseline_exe_sha256': executable, 'candidate_exe_sha256': new['sha256'].lower(), 'baseline_points': capture['points'], 'candidate_points': scale['baseline_points'], 'dpi': capture['dpi']}, indent=2))
    print('FONT BASELINE VERIFIED: published package, isolated runtime and fresh candidate')


if __name__ == '__main__':
    check(Path(sys.argv[1]), Path(sys.argv[2]))
