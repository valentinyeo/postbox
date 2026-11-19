import argparse
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

import verdict

PREFIX = 'verify-wazig-'
EXPECTED = {'planted': 'FAIL', 'clean': 'PASS'}
MODELS = dict(verdict.JUDGES)


def repo_args():
    repo = os.environ.get('GITHUB_REPOSITORY', '').strip()
    return ['-R', repo] if repo else []


def download_artifacts(run, target, gh=verdict.gh):
    target = Path(target)
    target.mkdir(parents=True, exist_ok=True)
    gh('run', 'download', str(run), '--pattern', PREFIX + '*', '--dir', str(target), *repo_args())


def case_inputs(name, run, pr, evidence_dir, download=download_artifacts, gh=verdict.gh):
    root = Path(evidence_dir) / name
    download(run, root)
    info = json.loads(gh('pr', 'view', str(pr), '--json', 'title,body', *repo_args()))
    pr_text = f"Title: {info.get('title') or ''}\n\n{info.get('body') or ''}"
    return root, pr_text, gh('pr', 'diff', str(pr), *repo_args())


def journeys_of(root):
    return [path.name[len(PREFIX):] for path in sorted(Path(root).glob(PREFIX + '*')) if path.is_dir()]


def evaluate(family, case, root, pr_text, diff, key, post, sleep):
    evidence = verdict.digest(root)
    user = verdict.build_user(pr_text, journeys_of(root), evidence, diff)
    model = MODELS[family]
    _, reply, errors = verdict.ask((model,), verdict.build_system(), user, key, post, sleep)
    if reply is None:
        print(f'judge-eval: {case} {family} {model} gave no verdict: ' + '; '.join(errors), file=sys.stderr)
        return {'family': family, 'model': model, 'case': case, 'verdict': 'FAIL', 'quote': '', 'ok': False}
    quote = reply[2]
    result = verdict.combine('PASS', [], reply, evidence)[0]
    ok = result == EXPECTED[case] and (case != 'planted' or (bool(quote) and quote in evidence))
    return {'family': family, 'model': model, 'case': case, 'verdict': result, 'quote': quote, 'ok': bool(ok)}


def summary_table(records):
    rows = ['| Case | Family | Model | Verdict | As expected |', '| --- | --- | --- | --- | --- |']
    for record in records:
        ok = 'yes' if record['ok'] else 'no'
        rows.append(f"| {record['case']} | {record['family']} | {record['model']} | {record['verdict']} | {ok} |")
    return '\n'.join(rows) + '\n'


def run(args, post=verdict.http_post, download=download_artifacts, gh=verdict.gh, sleep=time.sleep):
    families = [item.strip() for item in args.families.split(',') if item.strip()]
    unknown = [family for family in families if family not in MODELS]
    if unknown or not families:
        print('judge-eval: unknown judge families: ' + ', '.join(unknown or ['none'])
              + '; known: ' + ', '.join(sorted(MODELS)) + '.', file=sys.stderr)
        return 1
    key = os.environ.get('VERDICT_API_KEY', '')
    records = []
    for case, run_id, pr in (('planted', args.planted_run, args.planted_pr), ('clean', args.clean_run, args.clean_pr)):
        root, pr_text, diff = case_inputs(case, run_id, pr, args.evidence_dir, download, gh)
        for family in families:
            records.append(evaluate(family, case, root, pr_text, diff, key, post, sleep))
    for record in records:
        print(json.dumps(record))
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with Path(summary).open('a', encoding='utf-8') as output:
            output.write(summary_table(records))
    return 0 if records and all(record['ok'] for record in records) else 1


def main(argv=None, post=verdict.http_post, download=download_artifacts, gh=verdict.gh, sleep=time.sleep):
    parser = argparse.ArgumentParser(description='Replay the saved planted and clean journeys through each judge family.')
    parser.add_argument('--planted-run', required=True, help='verify-wazig run id that carries the planted bug evidence')
    parser.add_argument('--planted-pr', required=True, help='pull request number the planted run verified')
    parser.add_argument('--clean-run', required=True, help='verify-wazig run id that carries the clean evidence')
    parser.add_argument('--clean-pr', required=True, help='pull request number the clean run verified')
    parser.add_argument('--families', default='openai,kimi', help='comma separated judge families to test')
    parser.add_argument('--evidence-dir', required=True, help='folder for the downloaded evidence, one subfolder per case')
    return run(parser.parse_args(argv), post, download, gh, sleep)


if __name__ == '__main__':
    raise SystemExit(main())
