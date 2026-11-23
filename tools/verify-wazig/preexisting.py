import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def job_feature(name):
    prefix = 'verify ('
    if not name.startswith(prefix) or not name.endswith(')'):
        return None
    feature, separator, evidence = name[len(prefix):-1].rpartition(', ')
    if not separator or evidence not in ('true', 'false') or not feature:
        return None
    return feature


def classify(feature, runs):
    ordered = [run for _, run in sorted(enumerate(runs), key=lambda item: (item[1].get('created_at') or '', -item[0]), reverse=True)]
    for run in ordered:
        matched = [job for job in run.get('jobs') or [] if job_feature(job.get('name') or '') == feature]
        decisive = [job for job in matched if job.get('conclusion') in ('success', 'failure')]
        if not decisive:
            continue
        url = run.get('url') or ''
        names = ', '.join(job.get('name') or '' for job in decisive)
        if all(job.get('conclusion') == 'failure' for job in decisive):
            return {'preexisting': True, 'decisive': True, 'detail': f'preexisting {feature} failed in {url} as {names}'}
        return {'preexisting': False, 'decisive': True, 'detail': f'not preexisting {feature}: passed in {url}'}
    return {'preexisting': False, 'decisive': False, 'detail': f'not preexisting {feature}: no completed run on the default branch includes it'}


def jobs_from_text(text):
    stripped = (text or '').strip()
    if not stripped:
        return []
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, list):
        return parsed
    if isinstance(parsed, dict):
        return [parsed]
    return [json.loads(line) for line in stripped.splitlines() if line.strip()]


def gh(args, run):
    result = run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError('gh failed')
    return result.stdout


def unavailable(feature, branch):
    return {'preexisting': False, 'decisive': True, 'detail': f'not preexisting {feature}: could not read runs on {branch}'}


def evaluate(feature, repo, branch, limit, run):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo or ''):
        return unavailable(feature, branch)
    if not branch or branch.startswith('-') or any(char in branch for char in '\n\r\x00'):
        return unavailable(feature, branch)
    bounded = max(1, min(int(limit), 50))
    try:
        listed = json.loads(gh([
            'gh', 'run', 'list', '-R', repo, '--workflow', 'verify.yml', '--branch', branch,
            '--status', 'completed', '--limit', str(bounded),
            '--json', 'databaseId,url,createdAt,headBranch,event',
        ], run) or '[]')
    except (RuntimeError, ValueError, OSError, json.JSONDecodeError):
        return unavailable(feature, branch)
    if not isinstance(listed, list):
        return unavailable(feature, branch)
    listed.sort(key=lambda row: (row.get('createdAt') or '') if isinstance(row, dict) else '', reverse=True)
    collected = []
    for row in listed:
        if not isinstance(row, dict):
            continue
        if row.get('event') == 'pull_request' or (row.get('headBranch') and row.get('headBranch') != branch):
            continue
        run_id = row.get('databaseId')
        if isinstance(run_id, bool) or not isinstance(run_id, int) or run_id <= 0:
            continue
        try:
            jobs = jobs_from_text(gh([
                'gh', 'api', '--paginate', f'repos/{repo}/actions/runs/{run_id}/jobs?per_page=100',
                '--jq', '.jobs[] | {name, conclusion}',
            ], run))
        except (RuntimeError, ValueError, OSError, json.JSONDecodeError):
            return unavailable(feature, branch)
        collected.append({'url': row.get('url') or '', 'created_at': row.get('createdAt') or '', 'jobs': jobs})
        found = classify(feature, collected)
        if found['decisive']:
            return found
    return classify(feature, collected)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--feature', required=True)
    parser.add_argument('--runs', type=Path)
    parser.add_argument('--repo')
    parser.add_argument('--branch')
    parser.add_argument('--limit', type=int, default=30)
    args = parser.parse_args(argv)
    try:
        if args.runs:
            result = classify(args.feature, json.loads(args.runs.read_text(encoding='utf-8')))
        elif args.repo and args.branch:
            result = evaluate(args.feature, args.repo, args.branch, args.limit, subprocess.run)
        else:
            result = classify(args.feature, [])
    except (OSError, ValueError, json.JSONDecodeError):
        result = unavailable(args.feature, args.branch or 'the default branch')
    print(result['detail'])
    return 0 if result['preexisting'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
