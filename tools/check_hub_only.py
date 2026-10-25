import argparse
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RETIRED = ('slack_win.zig', 'slack_oauth.zig', 'slack_oauth_win.zig', 'telegram.zig', 'telegram_stub.zig')
IMPORT = re.compile(r'@import\s*\(\s*"([^"\n]+\.zig)"\s*\)')
DIRECT = re.compile(r'td_json_client_|setTdlibParameters|apps\.connections\.open|oauth\.v2\.access|slack\.com(?![A-Za-z])|child_process\.(?:run|spawn)\s*\(|send_args\.build(?:Send|React)\s*\(|auth --idle-exit|session\.start\(a\.wacli_path')


def production_source(source):
    tokens = re.finditer(r"""//[^\n]*|\\\\[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z_0-9]*|[{}]""", source)
    depth = 0
    test_start = None
    end = 0
    pieces = []
    for token in tokens:
        text = token.group()
        if text == 'test' and depth == 0:
            test_start = token.start()
        elif text == '{':
            depth += 1
        elif text == '}':
            depth -= 1
            if depth == 0 and test_start is not None:
                pieces.append(source[end:test_start])
                end = token.end()
                test_start = None
    pieces.append(source[end:])
    return ''.join(pieces)


def verify_source(source):
    source = production_source(source)
    source = re.sub(r'std\.mem\.(?:eql|endsWith)\(u8, host, "\.?slack\.com"\)', 'false', source)
    assert not DIRECT.search(source), 'desktop direct connector remains'
    for name in IMPORT.findall(source):
        assert Path(name).name not in RETIRED, name


def verify(root=ROOT):
    for name in RETIRED:
        assert not (root / 'src' / name).exists(), name
    pending = [root / 'src/main.zig']
    seen = set()
    while pending:
        path = pending.pop().resolve()
        if path in seen:
            continue
        seen.add(path)
        source = path.read_text()
        verify_source(source)
        for name in IMPORT.findall(source):
            target = path.parent / name
            assert target.is_file(), f'missing import: {target}'
            pending.append(target)
    build = (root / 'build.zig').read_text()
    release = (root / '.github/workflows/release.yml').read_text()
    for source in (build, release):
        assert not re.search(r'tdlib|telegram-api-(?:id|hash)|TELEGRAM_API_', source, re.I), 'desktop still needs TDLib'
    assert not (root / '.github/workflows/tdlib-cache.yml').exists()
    assert '@import("hub.zig")' in (root / 'src/main.zig').read_text()
    assert '@import("winhttp.zig")' in (root / 'src/wa_hub_win.zig').read_text()
    return seen


def negative_controls():
    for source in ('const x = @import("telegram.zig");', 'td_json_client_create();', 'const host = "slack.com";', 'child_process.spawn(a.io, .{});', 'send_args.buildSend(&args, .{});', '"auth --idle-exit 10m"'):
        try:
            verify_source(source)
        except AssertionError:
            continue
        raise AssertionError('retired connector accepted: ' + source)

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fixtures = {
            'src/main.zig': 'const hub = @import("hub.zig"); const helper = @import("nested/helper.zig");',
            'src/hub.zig': '',
            'src/nested/helper.zig': 'const connector = @import("connector.zig");',
            'src/nested/connector.zig': '',
            'src/wa_hub_win.zig': 'const http = @import("winhttp.zig");',
            'build.zig': '',
            '.github/workflows/release.yml': '',
        }
        for name, source in fixtures.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
        assert len(verify(root)) == 4
        for name in ('src/main.zig', 'src/nested/connector.zig'):
            path = root / name
            original = path.read_text()
            path.write_text(original + '\nfn connect() void { td_json_client_create(); }')
            try:
                verify(root)
            except AssertionError as error:
                assert str(error) == 'desktop direct connector remains', str(error)
            else:
                raise AssertionError('connector fixture accepted: ' + name)
            path.write_text(original)
            print('RED FIXTURE REJECTED: ' + name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', type=Path)
    args = parser.parse_args()
    negative_controls()
    seen = verify()
    if args.binary:
        binary = args.binary.read_bytes()
        assert binary[:2] == b'MZ', 'not a Windows executable'
        for marker in (b'setTdlibParameters', b'td_json_client_create', b'apps.connections.open', b'oauth.v2.access', b'auth --idle-exit'):
            assert marker not in binary, f'direct connector in binary: {marker!r}'
        assert b'/v1/wazig/' in binary, 'unified hub missing from binary'
    print(f'HUB ONLY VERIFIED: {len(seen)} desktop source modules; retired connector controls rejected')


if __name__ == '__main__':
    main()
