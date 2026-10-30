import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    source = (root / 'src/main.zig').read_text()
    parts = []
    for name in ('messagesDirPath', 'unifiedNativePath', 'writeOutboxAtomic', 'saveUnifiedCandidate',
                 'unifiedNoReparse', 'unifiedReadAttachment', 'unifiedPrivateDirectory',
                 'unifiedWriteProtected', 'unifiedImportRecord', 'unifiedSourceMatches',
                 'mintSendId', 'acceptUnifiedSends'):
        start = source.index(f'fn {name}(')
        end = source.index('\n}\n', start) + 3
        parts.append(source[start:end])
    with tempfile.TemporaryDirectory(prefix='unified-windows-paths-') as directory:
        target = Path(directory)
        for name in ('outbox.zig', 'unified_snapshot.zig'):
            (target / name).write_text((root / 'src' / name).read_text())
        fixture = (root / 'tools/unified_windows_paths_test.zig').read_text()
        (target / 'test.zig').write_text(fixture + '\n' + '\n'.join(parts))
        subprocess.run([args.zig, 'test', str(target / 'test.zig'), '-lc', '-lkernel32'], check=True)


if __name__ == '__main__':
    main()
