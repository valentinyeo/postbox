import re
import sys
from datetime import date
from pathlib import Path

HINT = 'use valentinyeo/token-ladder/.github/actions/ladder-call@main'
KEY_ENVS = (
    'DEEPSEEK_API_KEY',
    'OPENROUTER_API_KEY',
    'AI_GATEWAY_API_KEY',
    'OPENCODE_API_KEY',
    'OPENAI_API_KEY',
    'ANTHROPIC_API_KEY',
    'GROQ_API_KEY',
)
RULES = (
    ('api.deepseek.com', re.compile(r'https?://api\.deepseek\.com')),
    ('ai-gateway.vercel.sh', re.compile(r'https?://ai-gateway\.vercel\.sh')),
    ('opencode.ai/zen', re.compile(r'https?://opencode\.ai/zen')),
    ('openrouter.ai/api', re.compile(r'https?://openrouter\.ai/api')),
    ('api.openai.com', re.compile(r'https?://api\.openai\.com')),
    ('api.anthropic.com', re.compile(r'https?://api\.anthropic\.com')),
    ('api.groq.com', re.compile(r'https?://api\.groq\.com')),
    ('api.z.ai', re.compile(r'https?://api\.z\.ai')),
)
KEY_ENV_ALT = '|'.join(re.escape(name) for name in KEY_ENVS)
KEY_READ = re.compile(
    rf'process\.env\.(?:{KEY_ENV_ALT})\b'
    rf'|process\.env\[[\'"](?:{KEY_ENV_ALT})[\'"]\]'
    rf'|os\.environ\[[\'"](?:{KEY_ENV_ALT})[\'"]\]'
    rf'|os\.environ\.get\([\'"](?:{KEY_ENV_ALT})[\'"]'
    rf'|os\.getenv\([\'"](?:{KEY_ENV_ALT})[\'"]'
    rf'|\benv\.(?:{KEY_ENV_ALT})\b'
)
ALLOW_FILE = Path('.github/ladder-call-allow')
ALLOW_LINE = re.compile(r'^([^:]+):([^:]+):(\d{4}-\d{2}-\d{2})\s*$')
YAML_ENV_VALUE = re.compile(r'^\s*(?:[A-Z][A-Z0-9_]*_API_KEY|[A-Z][A-Z0-9_]*_KEY)\s*:')


def scan_roots(repo):
    roots = []
    for name in ('.github', 'tools'):
        path = repo / name
        if path.is_dir():
            roots.append(path)
    return roots


def load_allow_file(repo, today):
    path = repo / ALLOW_FILE
    active = {}
    problems = []
    if not path.is_file():
        return active, problems
    try:
        lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    except OSError as exc:
        problems.append((path, 0, f'cannot read allow file: {exc}'))
        return active, problems
    for lineno, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        match = ALLOW_LINE.match(line)
        if not match:
            problems.append((path, lineno, 'invalid allow line'))
            continue
        rel, _reason, until_s = match.group(1), match.group(2), match.group(3)
        try:
            until = date.fromisoformat(until_s)
        except ValueError:
            problems.append((path, lineno, f'invalid date {until_s!r}'))
            continue
        if until < today:
            problems.append((path, lineno, f'expired allow for {rel}'))
            continue
        active[rel] = until
    return active, problems


def yaml_env_wiring_line(line):
    return bool(YAML_ENV_VALUE.match(line))


def scan_file(path, repo, allows):
    hits = []
    try:
        rel = path.relative_to(repo).as_posix()
    except ValueError:
        rel = path.as_posix()
    if rel in allows:
        return hits
    try:
        text = path.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return hits
    is_yaml = path.suffix in {'.yml', '.yaml'}
    for lineno, line in enumerate(text.splitlines(), 1):
        if is_yaml and yaml_env_wiring_line(line):
            continue
        for label, pattern in RULES:
            if pattern.search(line):
                hits.append((path, lineno, label, line.rstrip()))
        key_match = KEY_READ.search(line)
        if key_match:
            hits.append((path, lineno, f'direct model key ({key_match.group(0)})', line.rstrip()))
    return hits


def show(path, repo):
    try:
        return path.relative_to(repo).as_posix()
    except ValueError:
        return path.as_posix()


def main():
    repo = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
    today = date.today()
    allows, allow_problems = load_allow_file(repo, today)
    failures = []
    for path, lineno, msg in allow_problems:
        failures.append((path, lineno, 'allow-file', msg))
    for root in scan_roots(repo):
        for path in sorted(root.rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                failures.extend(scan_file(path, repo, allows))
    seen = set()
    for path, lineno, label, detail in failures:
        key = (path, lineno, label)
        if key in seen:
            continue
        seen.add(key)
        print(f'{show(path, repo)}:{lineno}: direct model call ({label}): {HINT}')
        print(f'  {detail}')
    if failures:
        raise SystemExit(1)
    print('check-ladder-calls: ok')


if __name__ == '__main__':
    main()
