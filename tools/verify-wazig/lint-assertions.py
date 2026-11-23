import argparse
import json
from pathlib import Path
import re
import sys


def balanced(text, start):
    closing = {'(': ')', '{': '}'}
    stack = [closing[text[start]]]
    quote = None
    index = start + 1
    while index < len(text):
        char = text[index]
        if char == '`':
            index += 2
            continue
        if quote:
            if char == quote:
                if index + 1 < len(text) and text[index + 1] == quote:
                    index += 2
                    continue
                quote = None
        elif char in "\"'":
            quote = char
        elif char in closing:
            stack.append(closing[char])
        elif char in ')}':
            if char == stack[-1]:
                stack.pop()
                if not stack:
                    return text[start + 1:index], index + 1
        index += 1
    raise ValueError('Unclosed assertion expression')


def normalize(text):
    return re.sub(r'\s+', ' ', text).strip()


def assertions(text):
    pattern = r'\b(Assert-That|Wait-Until|if)\s*([({])'
    for match in re.finditer(pattern, text, re.I):
        command = match[1].lower()
        if command == 'if' and match[2] != '(':
            continue
        if command == 'assert-that' and match[2] != '(':
            continue
        if command == 'wait-until' and match[2] != '{':
            continue
        expression, end = balanced(text, match.end() - 1)
        if command == 'if' and not re.match(r'\s*{\s*throw\b', text[end:], re.I):
            continue
        yield text.count('\n', 0, match.start()) + 1, normalize(expression)


def proxy(expression):
    value = expression.lower().strip()
    while value.startswith('('):
        try:
            inner, end = balanced(value, 0)
        except ValueError:
            return None
        if end != len(value):
            break
        value = inner.strip()
    parts = re.split(r'\s+-(?:and|or)\s+', value)
    if len(parts) > 1 and all(proxy(part) for part in parts):
        return 'proxy checks alone'
    exit_check = r'\$(?:[\w.]+\.exitcode|lastexitcode|buildexit|exitcode|exit|code)\s+-(?:c|i)?(?:eq|ne)\s+\d+'
    if re.fullmatch(exit_check, value) or (re.search(r'&\s+python\b', value) and re.search(exit_check + r'$', value)):
        return 'exit code alone'
    if re.fullmatch(r'\$[\w.]+\.(?:ok|success)|\$\?', value):
        return 'success flag alone'
    if re.fullmatch(r'-not\s+\$(?:error|errors|failed|haserror)|\$(?:error|errors)\.count\s+-eq\s+0|\$(?:error|errors)\s+-eq\s+\$null', value):
        return 'absence of errors alone'
    if re.search(r'\b(?:read-edit|composer_text|\w*text\w*|preview)\b|\$(?:before|after)(?![\w.])', value) and not re.search(r'\b(?:if|throw|return)\b|;', value):
        if re.search(r'\s+-(?:c|i)?ne\s+', value) and not re.search(r'\s+-(?:and|or)\s+', value):
            return 'changed or nonempty text alone'
        if re.fullmatch(r'.*\.length\s+-gt\s+0', value) or re.fullmatch(r'-not\s+\[string\]::isnullorempty\(.+\)', value):
            return 'nonempty text alone'
    return None


def check(root, allowlist):
    failures = []
    seen = set()
    allowed = {(row['file'], row['assertion']): row['reason'] for row in allowlist}
    if len(allowed) != len(allowlist):
        failures.append('duplicate proxy exception')
    for path in sorted(root.glob('*.ps1')):
        for line, expression in assertions(path.read_text(encoding='utf-8-sig')):
            kind = proxy(expression)
            if not kind:
                continue
            key = (path.name, expression)
            seen.add(key)
            reason = allowed.get(key, '')
            if len(reason.split()) < 8:
                failures.append(f'{path.name}:{line}: {kind}; assert the visible result or sent payload, or add an exact exception explaining its companion proof')
    for key in allowed.keys() - seen:
        failures.append(f'{key[0]}: stale proxy exception: {key[1]}')
    return failures


def main():
    parser = argparse.ArgumentParser(description='Reject proxy-only assertions in Windows journeys and their PowerShell helpers.')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    path = args.root / 'proxy-allowlist.json'
    allowlist = json.loads(path.read_text()) if path.exists() else []
    failures = check(args.root, allowlist)
    if failures:
        print('\n'.join(failures), file=sys.stderr)
        return 1
    print('Journey proxy assertions checked; exact, reasoned exceptions only.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
