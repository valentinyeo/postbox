#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(git rev-parse --show-toplevel)}
cd "$root"
python3 - <<'PY'
import ast
from pathlib import Path
import re
import sys

limits_path = Path('tools/source-text-limits.txt')
try:
    lines = [line.split() for line in limits_path.read_text().splitlines()]
    limits = {key: int(value) for key, value in lines}
    if len(lines) != 2 or set(limits) != {'build_zig_slices', 'python_zig_readers'} or any(value < 0 for value in limits.values()):
        raise ValueError('expected two nonnegative limits')
except (OSError, ValueError) as exc:
    sys.exit(f'check-no-source-text-tests: invalid {limits_path}: {exc}')

build = Path('build.zig').read_text()
build = re.sub(r'(?m)^\s*fn sourceSection\([^\n]*\).*?^}', '', build, flags=re.S)
slices = len(re.findall(r'\bsourceSection\s*\(|\bstd\.mem\.(?:indexOf|lastIndexOf|indexOfScalar)\s*\(', build))

readers = []
for path in sorted(set(Path('tools').glob('test_*.py')) | set(Path('tools').glob('check_*.py'))):
    tree = ast.parse(path.read_text(), filename=str(path))
    zig_names = set()
    nodes = list(ast.walk(tree))
    def zig_path(node):
        return any((isinstance(part, ast.Constant) and isinstance(part.value, str) and (part.value.endswith('.zig') or part.value == '*.zig')) or (isinstance(part, ast.Name) and part.id in zig_names) for part in ast.walk(node))
    for _ in range(2):
        for node in nodes:
            if isinstance(node, (ast.Assign, ast.AnnAssign)) and node.value and zig_path(node.value):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                zig_names.update(part.id for target in targets for part in ast.walk(target) if isinstance(part, ast.Name))
    for node in nodes:
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        name = func.id if isinstance(func, ast.Name) else func.attr if isinstance(func, ast.Attribute) else ''
        if name in {'read_text', 'read_bytes', 'open', 'read', 'source'} and zig_path(node):
            readers.append(path)
            break

counts = {'build_zig_slices': slices, 'python_zig_readers': len(readers)}
failed = False
for key, count in counts.items():
    limit = limits[key]
    print(f'check-no-source-text-tests: {key} {count} (limit {limit})')
    if count > limit:
        print('check-no-source-text-tests: test the function: add a pure function with a behavior test, like src/chat_screen.zig; do not slice or read source text. Lower the limit when you remove cases.', file=sys.stderr)
        failed = True
    elif count < limit:
        print(f'check-no-source-text-tests: lower the limit for {key} to {count} when you remove cases')
sys.exit(failed)
PY
