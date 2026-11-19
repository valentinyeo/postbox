#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORMAL_DIR = Path(__file__).resolve().parent
COVERAGE = FORMAL_DIR / 'coverage.json'
JAR_URL = 'https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar'
JAR_SHA256 = '936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88'
PASS_TEXT = 'Model checking completed. No error has been found.'

MODELS = {
    'send-queue': {
        'module': 'SendQueue',
        'mutants': [
            ('hub-does-not-dedupe', 'HubDedupes', 'FALSE', 'NoDouble'),
            ('retry-mints-fresh-id', 'AutoFreshId', 'TRUE', 'NoDouble'),
            ('ack-on-ambiguous-result', 'AckOnAmbiguous', 'TRUE', 'NoLoss'),
            ('drop-record-on-give-up', 'DropOnGiveUp', 'TRUE', 'NoLoss'),
            ('retry-without-attempt-bound', 'NoAttemptBound', 'TRUE', 'AutoSendsBounded'),
            ('dispatch-while-inflight', 'DispatchWhileInflight', 'TRUE', 'SingleInflight'),
        ],
    },
    'transcribe-retry': {
        'module': 'TranscribeRetry',
        'mutants': [
            ('attempt-not-recorded', 'RecordAttempt', 'FALSE', 'OneRequestPerOpen'),
            ('reopen-clears-ready', 'ReopenClearsReady', 'TRUE', 'NeverRerequestReady'),
            ('parallel-requests', 'ParallelRequests', 'TRUE', 'OneAtATime'),
        ],
    },
}


def function_body(text, name):
    lines = text.split('\n')
    start = None
    indent = ''
    for index, line in enumerate(lines):
        match = re.match(r'^(\s*)(pub )?fn ' + re.escape(name) + r'\(', line)
        if match:
            start = index
            indent = match.group(1)
            break
    if start is None:
        return None
    for end in range(start, len(lines)):
        if lines[end] == indent + '}' or (end == start and lines[end].rstrip().endswith('}')):
            return '\n'.join(line.rstrip() for line in lines[start:end + 1])
    return None


def body_hash(body):
    return hashlib.sha256(body.encode()).hexdigest()


def sync_report(root=ROOT, coverage_path=COVERAGE):
    coverage = json.loads(Path(coverage_path).read_text())
    problems = []
    for item in coverage['functions']:
        source = Path(root) / item['file']
        body = function_body(source.read_text(), item['name']) if source.exists() else None
        if body is None:
            problems.append(f"{item['file']}:{item['name']} is gone or moved; review {item['model']} and update coverage.json")
        elif body_hash(body) != item['sha256']:
            problems.append(f"{item['file']}:{item['name']} changed since sync commit {coverage['sync_commit'][:10]}; review {item['model']} and rerun with --update")
    return problems


def update_coverage(sync, root=ROOT, coverage_path=COVERAGE):
    coverage = json.loads(Path(coverage_path).read_text())
    coverage['sync_commit'] = sync
    for item in coverage['functions']:
        body = function_body((Path(root) / item['file']).read_text(), item['name'])
        if body is None:
            raise SystemExit(f"{item['file']}:{item['name']} not found")
        item['sha256'] = body_hash(body)
    Path(coverage_path).write_text(json.dumps(coverage, indent=2) + '\n')


def find_jar():
    override = os.environ.get('TLA2TOOLS_JAR')
    candidates = [Path(override)] if override else []
    candidates.append(Path.home() / '.cache' / 'postbox-formal' / 'tla2tools.jar')
    for path in candidates:
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == JAR_SHA256:
            return path
    target = candidates[-1]
    target.parent.mkdir(parents=True, exist_ok=True)
    data = urllib.request.urlopen(JAR_URL, timeout=120).read()
    if hashlib.sha256(data).hexdigest() != JAR_SHA256:
        raise SystemExit('tla2tools.jar hash mismatch; refusing to run it')
    target.write_bytes(data)
    return target


def run_tlc(jar, model, cfg_text):
    module = MODELS[model]['module']
    with tempfile.TemporaryDirectory() as work:
        cfg = Path(work) / (module + '.cfg')
        cfg.write_text(cfg_text)
        tla = Path(work) / (module + '.tla')
        tla.write_text((FORMAL_DIR / model / (module + '.tla')).read_text())
        proc = subprocess.run(
            ['java', '-XX:+UseParallelGC', '-cp', str(jar), 'tlc2.TLC', '-workers', 'auto', '-deadlock',
             '-metadir', str(Path(work) / 'states'), '-config', str(cfg), str(tla)],
            capture_output=True, text=True, cwd=work)
    return proc.stdout + proc.stderr


def mutant_config(base, constant, value):
    pattern = re.compile(r'^(\s*' + constant + r' = )\w+$', re.M)
    if not pattern.search(base):
        raise SystemExit(f'{constant} is missing from the model cfg')
    return pattern.sub(lambda match: match.group(1) + value, base)


def strip_properties(cfg_text):
    return '\n'.join(line for line in cfg_text.split('\n') if not line.startswith('PROPERTIES'))


def violated(output):
    match = re.search(r'Invariant (\w+) is violated', output)
    if match:
        return match.group(1)
    if 'Temporal properties were violated' in output:
        return 'temporal'
    return None


def run_models(only=None, show_trace=False):
    jar = find_jar()
    failures = 0
    for model, spec in MODELS.items():
        base = (FORMAL_DIR / model / (spec['module'] + '.cfg')).read_text()
        if only in (None, model):
            output = run_tlc(jar, model, base)
            ok = PASS_TEXT in output
            print(('PASS' if ok else 'FAIL') + f' {model}: every property holds')
            if not ok or show_trace:
                print(output)
            failures += 0 if ok else 1
        for name, constant, value, invariant in spec['mutants']:
            if only not in (None, model, name):
                continue
            output = run_tlc(jar, model, strip_properties(mutant_config(base, constant, value)))
            got = violated(output)
            ok = got == invariant
            print(('PASS' if ok else 'FAIL') + f' {model} / {name}: {constant}={value} must break {invariant}, broke {got}')
            if not ok or show_trace:
                print(output)
            failures += 0 if ok else 1
    return failures


def main():
    parser = argparse.ArgumentParser(description='Check the formal models against the code and run them.')
    parser.add_argument('--tlc', action='store_true', help='run the model checker on every model and every broken variant')
    parser.add_argument('--only', help='run one model by folder name, or one broken variant by name')
    parser.add_argument('--trace', action='store_true', help='print the full checker output')
    parser.add_argument('--update', metavar='SYNC_COMMIT', help='record current function hashes after the models were confirmed to describe them')
    args = parser.parse_args()
    if args.update:
        update_coverage(args.update)
        print('coverage.json updated')
        return 0
    status = 0
    problems = sync_report()
    for problem in problems:
        print('DRIFT ' + problem)
    status |= 1 if problems else 0
    if not problems:
        print('PASS covered code matches the recorded hashes')
    if args.tlc or args.only:
        status |= 1 if run_models(args.only, args.trace) else 0
    return status


if __name__ == '__main__':
    sys.exit(main())
