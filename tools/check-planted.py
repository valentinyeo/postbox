import json
from pathlib import Path
import sys


def check(root):
    folder = root / 'tools/verify-wazig'
    journeys = {row['name'] for row in json.loads((folder / 'journeys.json').read_text(encoding='utf-8'))['journeys']}
    patches = list((folder / 'planted').glob('*.patch'))
    names = {patch.stem for patch in patches}
    errors = []
    for patch in patches:
        if patch.stem not in journeys:
            errors.append(f'{patch.name}: unknown journey')
        if not patch.with_suffix('.txt').is_file() or not patch.with_suffix('.txt').read_text(encoding='utf-8').strip():
            errors.append(f'{patch.name}: missing description')
        if not patch.read_text(encoding='utf-8').startswith('diff --git a/src/'):
            errors.append(f'{patch.name}: expected a src patch')
    limit = int((folder / 'planted-limits.txt').read_text(encoding='utf-8').strip())
    missing = len(journeys - names)
    if missing > limit:
        errors.append(f'{missing} journeys lack patches; limit is {limit}')
    return errors


if __name__ == '__main__':
    failures = check(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    if failures:
        sys.exit('\n'.join(failures))
    print('planted patch coverage passed')
