import json
import os
from pathlib import Path


def verdict(needs):
    notes = []
    for name in ('plan', 'base-fails', 'verify'):
        result = needs[name]['result']
        if result == 'skipped' and name == 'verify' and needs['plan']['outputs'].get('needed') == 'false':
            continue
        if result != 'success':
            return 'FAIL', [f'{name}: {result}']
    notes.extend(json.loads(needs['plan']['outputs'].get('notes') or '[]'))
    if needs['plan']['outputs'].get('repro') and needs['base-fails']['outputs'].get('classified') != 'true':
        notes.append('Base reproduction could not be classified.')
    return ('PASS+NOTES' if notes else 'PASS'), notes


def main():
    result, notes = verdict(json.loads(os.environ['NEEDS_JSON']))
    summary = result + '\n' + ''.join(f'\n- {note}\n' for note in notes)
    print(summary)
    with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a', encoding='utf-8') as output:
        output.write(summary)
    return int(result == 'FAIL')


if __name__ == '__main__':
    raise SystemExit(main())
