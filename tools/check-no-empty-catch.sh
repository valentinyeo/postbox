#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(git rev-parse --show-toplevel)}
cd "$root"
python3 - <<'PY'
from pathlib import Path
import re
import sys

limits_path = Path('tools/empty-catch-limits.txt')
try:
    lines = [line.split() for line in limits_path.read_text().splitlines()]
    limits = {key: int(value) for key, value in lines}
    if len(lines) != len(limits) or 'total' not in limits or any(value < 0 for value in limits.values()):
        raise ValueError('expected unique nonnegative limits and a total')
    if any(key != 'total' and not re.fullmatch(r'src/[^/\s]+\.zig', key) for key in limits):
        raise ValueError('expected src/*.zig paths')
except (OSError, ValueError) as exc:
    sys.exit(f'check-no-empty-catch: invalid {limits_path}: {exc}')

pattern = re.compile(r'\bcatch\s*(?:\|\s*[A-Za-z_][A-Za-z_0-9]*\s*\|\s*)?\{\s*\}')
counts = {}
for path in sorted(Path('src').glob('*.zig')):
    source = path.read_text()
    masked = list(source)
    i = 0
    while i < len(source):
        start = i
        if source.startswith('//', i) or source.startswith('\\\\', i):
            end = source.find('\n', i)
            i = len(source) if end < 0 else end
        elif source[i] in ('"', "'"):
            quote = source[i]
            i += 1
            while i < len(source):
                if source[i] == '\\':
                    i += 2
                elif source[i] == quote:
                    i += 1
                    break
                else:
                    i += 1
        else:
            i += 1
            continue
        masked[start:i] = [' ' if char != '\n' else '\n' for char in source[start:i]]
    counts[str(path)] = len(pattern.findall(''.join(masked)))
counts['total'] = sum(counts.values())
failed = False
for key in sorted(set(counts) | set(limits), key=lambda key: (key == 'total', key)):
    count = counts.get(key, 0)
    limit = limits.get(key, 0)
    if count or limit or key == 'total':
        print(f'check-no-empty-catch: {key} {count} (limit {limit})')
    if count > limit:
        print("check-no-empty-catch: handle the error: log it with the app's log function, return it, or use `catch |err| log(...)`; do not swallow it with an empty catch. Lower the limit when you remove cases.", file=sys.stderr)
        failed = True
    elif count < limit:
        print(f'check-no-empty-catch: lower the limit for {key} to {count} when you remove cases')
sys.exit(failed)
PY
