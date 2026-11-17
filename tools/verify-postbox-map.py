#!/usr/bin/env python3
"""Inventory bounded Zig entry patterns. This is not the shared gate's Zig adapter."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FEATURES = ROOT / '.cursor/skills/verify-postbox/features'
TOKEN = re.compile(r'//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|\\\\[^\n]*')


def masked(text):
    return TOKEN.sub(lambda m: ''.join('\n' if c == '\n' else ' ' for c in m[0]), text)


def closing(code, start, left='(', right=')'):
    depth = 0
    for index in range(start, len(code)):
        depth += code[index] == left
        depth -= code[index] == right
        if depth == 0:
            return index
    raise ValueError(f'Unbalanced {left} at {start}')


def discover():
    entries = {}
    paths = sorted((ROOT / 'src').glob('*.zig'))
    for path in paths:
        if path.stem.endswith('_test'):
            continue
        text = path.read_text()
        code = masked(text)
        for match in re.finditer(r'\btest\s+[^\{]*\{', code):
            end = closing(code, match.end() - 1, '{', '}')
            code = code[:match.start()] + ''.join('\n' if c == '\n' else ' ' for c in code[match.start():end + 1]) + code[end + 1:]
        functions = list(re.finditer(r'\bfn\s+(\w+)\s*\(', code))

        def add(kind, start, label, identity=None):
            line = text.count('\n', 0, start) + 1
            column = start - text.rfind('\n', 0, start)
            owner = next((m[1] for m in reversed(functions) if m.start() < start), 'module')
            identifier = identity or f'{owner}@{line}:{column}'
            key = (kind, identifier, path.relative_to(ROOT).as_posix())
            entries[key] = {'kind': kind, 'id': identifier, 'source': key[2], 'line': line,
                            'reach': re.sub(r'\s+', ' ', label).strip()}

        calls = r'\b(appendPalette|appendMessageMenuItem|AppendMenuW|CreateWindowExW|SetTimer|RegSetValueExW|saveSecret)\s*\('
        for match in re.finditer(calls, code):
            if re.search(r'\bfn\s*$', code[max(0, match.start() - 10):match.start()]):
                continue
            end = closing(code, match.end() - 1)
            body = text[match.end():end]
            literals = re.findall(r'"((?:\\.|[^"\\])*)"', body)
            label = ' / '.join(value for value in literals if value) or body
            call = match[1]
            if call == 'appendPalette':
                if re.search(r',\s*0\s*$', body) and 'view' not in body and 'label' not in body:
                    continue
                add('command', match.start(), label)
            elif call in {'appendMessageMenuItem', 'AppendMenuW'}:
                if 'MF_SEPARATOR' in body or re.search(r',\s*0\s*,\s*null\s*$', body):
                    continue
                add('menu', match.start(), label)
            elif call == 'CreateWindowExW':
                if 'TOOLTIPS_CLASS' in body or 'smoke' in body or 'test' in body:
                    continue
                kind = 'button' if '"BUTTON"' in body else 'screen'
                add(kind, match.start(), label)
            elif call == 'SetTimer':
                timer = re.search(r'\btimer_\w+', body)
                if timer:
                    add('job', match.start(), timer[0], timer[0])
            elif call in {'RegSetValueExW', 'saveSecret'} and literals:
                add('setting', match.start(), literals[0], literals[0])

        for match in re.finditer(r'\.key\s*=\s*', code):
            row = text[match.end():text.find('\n', match.end())]
            strings = re.findall(r'"((?:\\.|[^"\\])*)"', row)
            if path.name == 'shortcuts.zig' and len(strings) >= 2:
                add('shortcut', match.start(), strings[0] + ': ' + strings[1], strings[0])
        if path.name == 'control.zig':
            for match in re.finditer(r'\.cmd\s*=\s*\.', code):
                row = text[match.end():text.find('\n', match.end())]
                usage = re.search(r'\.usage = "([^"]+)"', row)
                if usage:
                    add('command', match.start(), 'postboxctl ' + usage[1], 'postboxctl ' + usage[1].split()[0])
                    add('endpoint', match.start(), 'Local named pipe: ' + usage[1], 'control-pipe ' + usage[1].split()[0])
        if path.name == 'main.zig':
            jobs = re.search(r'const WacliJobKind = enum\(u8\) \{([^}]+)\}', text)
            if jobs:
                for job in jobs[1].split(','):
                    add('job', jobs.start(), job.strip(), 'provider ' + job.strip())
            for match in re.finditer(r'\bif\s*\(', code):
                end = closing(code, match.end() - 1)
                condition = text[match.end():end]
                if re.search(r'\bkey\s*(?:==|>=|<=)|\bhit\.|\bpointInRect\b|\bPtInRect\b', condition):
                    kind = 'shortcut' if re.search(r'\bkey\s*(?:==|>=|<=)', condition) else 'button'
                    add(kind, match.start(), condition)
    return sorted(entries.values(), key=lambda row: (row['kind'], row['source'], row['line'], row['id']))


def mapped():
    result = []
    for path in FEATURES.glob('*.md'):
        result.extend(re.findall(r'<!-- entry: (\w+)\|([^|]+)\|([^>]+) -->', path.read_text()))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    rows = discover()
    if args.write:
        FEATURES.mkdir(parents=True, exist_ok=True)
        index = ['# Postbox entry inventory', '', 'Source-derived inventory. Shared Zig coverage remains blocked.', '',
                 'Dynamic rows represent factories, not account counts.', 'Routes are absent. This is a native desktop.', '',
                 'The scanner covers bounded Zig patterns only.', 'Custom handlers still need semantic adapter review.', '',
                 'Regenerate with `python3 tools/verify-postbox-map.py --write`.', 'Check with `python3 tools/verify-postbox-map.py`.', '']
        for kind in sorted({row['kind'] for row in rows}):
            subset = [row for row in rows if row['kind'] == kind]
            name = kind + '.md'
            index.append(f'- [{kind}: {len(subset)} entries]({name})')
            body = [f'# Postbox {kind} entries', '', '## Sub-features', '']
            for row in subset:
                body.extend([f"<!-- entry: {kind}|{row['id']}|{row['source']} -->",
                             f"- `{row['source']}:{row['line']}`: {row['reach']}", ''])
            body.extend(['## How to get to it (user POV)', '',
                         'Launch Postbox. Use the listed control or command.',
                         'Conditional entries require their matching provider state.', '',
                         '## Driving it with PowerShell UI Automation', '',
                         'Use the real Windows harness, never internal setters.',
                         'Read [the skill](../SKILL.md) before driving.',
                         'Match the source label through keyboard or UIA.',
                         'Inspect resulting screenshots and persisted side effects.',
                         'CLI entries use the listed postboxctl command.',
                         'Jobs need their user action and resulting state.', '',
                         '## Gotchas', '',
                         'An inventory entry does not prove execution.',
                         'The shared gate cannot scan Zig yet.',
                         'These are bounded scanner results, not semantic completeness.',
                         'Existing journeys document narrower proof and gaps.', ''])
            (FEATURES / name).write_text('\n'.join(body))
        (FEATURES / 'README.md').write_text('\n'.join(index) + '\n')
    expected = {(r['kind'], r['id'], r['source']) for r in rows}
    actual = mapped()
    missing, dead = sorted(expected - set(actual)), sorted(set(actual) - expected)
    if missing or dead or len(actual) != len(set(actual)):
        print(json.dumps({'missing': missing, 'dead': dead, 'duplicate_count': len(actual) - len(set(actual))}, indent=2))
        return 1
    print(json.dumps({'entries': len(rows), 'by_kind': dict(Counter(r['kind'] for r in rows)),
                      'shared_gate_coverage': 'BLOCKED: no Zig adapter', 'rows': rows} if args.json else
                     {'entries': len(rows), 'by_kind': dict(Counter(r['kind'] for r in rows)),
                      'result': 'PASS bounded inventory; semantic completeness unverified'}, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
