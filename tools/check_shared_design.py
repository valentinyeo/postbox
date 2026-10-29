import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request


def validate(root, upstream=False):
    root = Path(root)
    manifest_path = root / 'shared-design.json'
    assert manifest_path.is_file(), 'Missing Multiprompt-owned design manifest'
    manifest = json.loads(manifest_path.read_text())
    assert manifest['repository'] == 'valentinyeo/multiprompt'
    assert re.fullmatch(r'[0-9a-f]{40}', manifest['commit'])
    assert manifest['path'] == 'src/design_tokens.zig'
    shared = root / manifest['path']
    assert shared.is_file(), 'Missing vendored design module'
    content = shared.read_bytes()
    assert hashlib.sha256(content).hexdigest() == manifest['sha256'], 'Vendored design hash mismatch'
    if upstream:
        url = f"https://raw.githubusercontent.com/{manifest['repository']}/{manifest['commit']}/{manifest['path']}"
        with urllib.request.urlopen(url, timeout=30) as response:
            assert response.headers.get_content_type() == 'text/plain'
            original = response.read()
        assert original == content, 'Vendored module differs from pinned Multiprompt source'
    for name, painter in [('main.zig', 'design.micPill('), ('theme.zig', 'design.ReaderForeground')]:
        assert painter in (root / 'src' / name).read_text(), f'{name} does not consume the shared design'
    allowed = {
        'theme.zig': 'contrast-reference fixtures and RGB bit masks only',
        'text_draw.zig': 'text backend test fixture colours only',
        'smooth_shapes.zig': 'graphics backend test fixture colour only',
        'directwrite_edit.zig': 'backend pixel comparisons only',
    }
    literal = re.compile(r'(?<![\w])0x[0-9a-fA-F]{6}(?![0-9a-fA-F])|\brgb\(\s*\d|\.r\s*=\s*\d+\s*,\s*\.g\s*=')
    for path in (root / 'src').glob('*.zig'):
        if path.name == manifest['path'].split('/')[-1]:
            continue
        source = path.read_text()
        if path.name in allowed:
            source = source.split('\ntest ', 1)[0]
            source = re.sub(r'\(\(value & 0xff0000\) >> 16\) \| \(value & 0x00ff00\) \| \(\(value & 0x0000ff\) << 16\)', '', source)
        source = re.sub(r'& 0x(?:ffffff|ff0000|00ff00|0000ff)\b', '', source, flags=re.I)
        assert not literal.search(source), f'UI colour literal outside shared module: {path.name}'
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--upstream', action='store_true')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    validate(args.root, args.upstream)
    print('SHARED_DESIGN_OK')
