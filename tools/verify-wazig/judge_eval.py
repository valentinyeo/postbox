import argparse
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

import verifier

PREFIX = 'verify-wazig-'
EXPECTED = {'planted': 'FAIL', 'clean': 'PASS'}
DEFAULT_FAMILY_COUNT = 2


def repo_args():
    repo = os.environ.get('GITHUB_REPOSITORY', '').strip()
    return ['-R', repo] if repo else []


def download_artifacts(run, target, gh=verifier.gh):
    target = Path(target)
    target.mkdir(parents=True, exist_ok=True)
    gh('run', 'download', str(run), '--pattern', PREFIX + '*', '--dir', str(target), *repo_args())


def case_inputs(name, run, pr, evidence_dir, download=download_artifacts, gh=verifier.gh):
    root = Path(evidence_dir) / name
    download(run, root)
    info = json.loads(gh('pr', 'view', str(pr), '--json', 'title,body', *repo_args()))
    pr_text = f"Title: {info.get('title') or ''}\n\n{info.get('body') or ''}"
    return root, pr_text, gh('pr', 'diff', str(pr), *repo_args()), run_needs(run, journeys_of(root), gh)


def journeys_of(root):
    return [path.name[len(PREFIX):] for path in sorted(Path(root).glob(PREFIX + '*')) if path.is_dir()]


def run_needs(run, journeys, gh=verifier.gh):
    jobs = json.loads(gh('run', 'view', str(run), '--json', 'jobs', *repo_args())).get('jobs') or []
    plan = next((job.get('conclusion') for job in jobs if job.get('name') == 'plan'), 'failure')
    legs = [job.get('conclusion') for job in jobs if str(job.get('name') or '').startswith('verify (')]
    if legs and all(result == 'success' for result in legs):
        verify = 'success'
    elif legs and any(result != 'skipped' for result in legs):
        verify = 'failure'
    else:
        verify = 'failure' if journeys else 'skipped'
    return {'plan': {'result': plan, 'outputs': {'needed': 'false' if verify == 'skipped' else 'true'}},
            'verify': {'result': verify, 'outputs': {}}}


def parse_families(raw):
    requested = [item.strip() for item in (raw or '').split(',') if item.strip()]
    unknown = [family for family in requested if family not in verifier.FAMILY_NAMES]
    if unknown:
        raise ValueError('unknown judge families: ' + ', '.join(unknown)
                         + '; known: ' + ', '.join(sorted(verifier.FAMILY_NAMES)) + '.')
    return list(dict.fromkeys(requested))


def pick_family_judges(requested, listed):
    all_families = set(verifier.FAMILY_NAMES)
    if requested:
        families = requested
    else:
        all_judges, _ = verifier.pick_judges(set(), listed)
        families = []
        for model in all_judges:
            for family in sorted(verifier.family_of(model)):
                if family not in families:
                    families.append(family)
        if len(families) < DEFAULT_FAMILY_COUNT:
            raise ValueError(f'need at least {DEFAULT_FAMILY_COUNT} judge families; available: '
                             + (', '.join(families) or 'none') + '.')
        families = families[:DEFAULT_FAMILY_COUNT]
    plan = []
    for family in families:
        try:
            judges, _ = verifier.pick_judges(all_families - {family}, listed)
        except ValueError as error:
            raise ValueError(f'no judge model available for family {family}: {error}') from error
        plan.append((family, judges))
    return plan


def evaluate(family, judges, case, root, pr_text, diff, needs, key, post, sleep, say):
    evidence = verifier.digest(root)
    result, notes, quotes = verifier.journey_gate(needs, evidence)
    quote = quotes[0] if quotes else ''
    model = None
    if result != 'FAIL':
        user = verifier.build_user(pr_text, journeys_of(root), evidence, diff)
        model, reply, errors = verifier.ask(judges, verifier.build_system(), user, key, post, sleep, say)
        if reply is None:
            print(f'judge-eval: {case} {family} gave no verdict: ' + '; '.join(errors), file=sys.stderr)
            return {'family': family, 'model': judges[0], 'case': case, 'verdict': 'FAIL', 'quote': '', 'notes': errors, 'ok': False}
        quote = reply[2]
        result, notes = verifier.combine('PASS', [], reply, evidence)
    ok = result == EXPECTED[case] and (case != 'planted' or (bool(quote) and quote in evidence))
    return {'family': family, 'model': model or 'none (the journey evidence decided)', 'case': case,
            'verdict': result, 'quote': quote, 'notes': notes, 'ok': bool(ok)}


def summary_table(records):
    rows = ['| Case | Family | Model | Verdict | As expected |', '| --- | --- | --- | --- | --- |']
    for record in records:
        ok = 'yes' if record['ok'] else 'no'
        rows.append(f"| {record['case']} | {record['family']} | {record['model']} | {record['verdict']} | {ok} |")
    return '\n'.join(rows) + '\n'


def run(args, post=verifier.http_post, download=download_artifacts, gh=verifier.gh, sleep=time.sleep,
        fetch=verifier.fetch_models, say=None):
    say = say or (lambda line: print(line, file=sys.stderr))
    try:
        requested = parse_families(args.families)
    except ValueError as error:
        print(f'judge-eval: {error}', file=sys.stderr)
        return 1
    key = os.environ.get('VERDICT_API_KEY', '').strip()
    if not key:
        print('judge-eval: VERDICT_API_KEY is empty.', file=sys.stderr)
        return 1
    listed, why = verifier.catalogue(key, fetch)
    if listed:
        say(f'judge-eval: Groq lists {len(listed)} models; choosing judges from that list')
    else:
        say(f'judge-eval: the Groq model list failed ({why}); falling back to the static judge list')
    try:
        plan = pick_family_judges(requested, listed)
    except ValueError as error:
        print(f'judge-eval: {error}', file=sys.stderr)
        return 1
    for family, judges in plan:
        say(f'judge-eval: {family} judges: ' + ', '.join(judges))
    records = []
    for case, run_id, pr in (('planted', args.planted_run, args.planted_pr), ('clean', args.clean_run, args.clean_pr)):
        root, pr_text, diff, needs = case_inputs(case, run_id, pr, args.evidence_dir, download, gh)
        for family, judges in plan:
            records.append(evaluate(family, judges, case, root, pr_text, diff, needs, key, post, sleep, say))
    for record in records:
        print(json.dumps(record))
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with Path(summary).open('a', encoding='utf-8') as output:
            output.write(summary_table(records))
    return 0 if records and all(record['ok'] for record in records) else 1


def main(argv=None, post=verifier.http_post, download=download_artifacts, gh=verifier.gh, sleep=time.sleep,
         fetch=verifier.fetch_models, say=None):
    parser = argparse.ArgumentParser(description='Replay the saved planted and clean journeys through each judge family.')
    parser.add_argument('--planted-run', required=True, help='verify-wazig run id that carries the planted bug evidence')
    parser.add_argument('--planted-pr', required=True, help='pull request number the planted run verified')
    parser.add_argument('--clean-run', required=True, help='verify-wazig run id that carries the clean evidence')
    parser.add_argument('--clean-pr', required=True, help='pull request number the clean run verified')
    parser.add_argument('--families', default='', help='comma separated judge families to test, or empty for two live families')
    parser.add_argument('--evidence-dir', required=True, help='folder for the downloaded evidence, one subfolder per case')
    return run(parser.parse_args(argv), post, download, gh, sleep, fetch, say)


if __name__ == '__main__':
    raise SystemExit(main())
