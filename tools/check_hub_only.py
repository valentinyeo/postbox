import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RETIRED = ('slack_win.zig', 'slack_oauth.zig', 'slack_oauth_win.zig', 'telegram.zig', 'telegram_stub.zig')
DIRECT = re.compile(r'td_json_client_|setTdlibParameters|apps\.connections\.open|oauth\.v2\.access|slack\.com(?![A-Za-z])|child_process\.(?:run|spawn)\s*\(|send_args\.build(?:Send|React)\s*\(|auth --idle-exit|session\.start\(a\.wacli_path')


def verify_source(source):
    assert not DIRECT.search(source), 'desktop direct connector remains'
    for name in RETIRED:
        assert '@import("' + name + '")' not in source, name


def verify(root=ROOT):
    for name in RETIRED:
        assert not (root / 'src' / name).exists(), name
    pending = [root / 'src/main.zig']
    seen = set()
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        source = path.read_text()
        if path.name in ('main.zig', 'winhttp.zig', 'wa_hub_win.zig', 'avatar.zig'):
            verify_source(source)
        for name in re.findall(r'@import\("([^"\n]+\.zig)"\)', source):
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
