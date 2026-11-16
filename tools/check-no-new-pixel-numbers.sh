#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(git rev-parse --show-toplevel)}
cd "$root"
python3 - <<'PY'
from pathlib import Path
import re
import sys

limits_path = Path('tools/pixel-number-limits.txt')
try:
    lines = [line.split() for line in limits_path.read_text().splitlines()]
    limits = {key: int(value) for key, value in lines}
    if len(lines) != len(limits) or not limits or any(value < 0 for value in limits.values()):
        raise ValueError('expected unique nonnegative function limits')
    if any(not re.fullmatch(r'(?:draw|paint)[A-Za-z0-9_]*', key) for key in limits):
        raise ValueError('expected drawing function names')
    source = Path('src/main.zig').read_text()
except (OSError, ValueError) as exc:
    sys.exit(f'check-no-new-pixel-numbers: invalid input: {exc}')

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
text = ''.join(masked)
functions = re.compile(r'\bfn\s+((?:draw|paint)[A-Za-z0-9_]*)\s*\([^;{}]*\)[^;{}]*\{')
numbers = re.compile(r'(?<![A-Za-z0-9_])(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+-]?[0-9_]+)?)(?![A-Za-z0-9_])')
counts = {}
for match in functions.finditer(text):
    name = match.group(1)
    if name in counts:
        sys.exit(f'check-no-new-pixel-numbers: duplicate function {name}')
    depth = 1
    end = match.end()
    while end < len(text) and depth:
        if text[end] == '{':
            depth += 1
        elif text[end] == '}':
            depth -= 1
        end += 1
    if depth:
        sys.exit(f'check-no-new-pixel-numbers: unclosed function {name}')
    counts[name] = len(numbers.findall(text[match.end():end - 1]))
failed = False
for name in sorted(counts.keys() | limits.keys()):
    count = counts.get(name, 0)
    limit = limits.get(name, 0)
    if count > limit:
        print(f'check-no-new-pixel-numbers: src/main.zig {name} has {count} numeric literals (limit {limit}); put layout numbers in src/box_layout.zig or src/quote_layout.zig', file=sys.stderr)
        failed = True
    elif count < limit:
        print(f'check-no-new-pixel-numbers: lower {name} limit to {count}')
print(f'check-no-new-pixel-numbers: {sum(counts.values())} numeric literals in drawing functions (limit {sum(limits.values())})')
sys.exit(failed)
PY
