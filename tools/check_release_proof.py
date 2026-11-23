import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/verify-wazig'))
from plan_journeys import plan_journeys


def run(command):
    return subprocess.check_output(command, text=True, stderr=subprocess.PIPE)


def api_pages(endpoint, runner, key=None):
    rows = []
    page = 1
    while True:
        separator = '&' if '?' in endpoint else '?'
        data = json.loads(runner(['gh', 'api', f'{endpoint}{separator}per_page=100&page={page}']))
        batch = data[key] if key else data
        rows.extend(batch)
        if len(batch) < 100:
            return rows
        page += 1


def version(tag):
    if not re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag):
        raise ValueError(f'{tag} is not a strict vX.Y.Z tag')
    return tuple(int(part) for part in tag[1:].split('.'))


def check_release_proof(repo, tag, previous=None, runner=run):
    target = version(tag)
    if previous is None:
        candidates = []
        for name in runner(['git', 'tag', '--list', 'v*']).splitlines():
            try:
                if version(name) < target:
                    candidates.append(name)
            except ValueError:
                continue
        previous = max(candidates, key=version) if candidates else None
    if previous is None:
        print(f'{tag}: first release; no previous tag, no proof range to check')
        return 0
    if version(previous) >= target:
        raise ValueError('previous tag must be below the release tag')
    mapping = json.loads((ROOT / 'tools/verify-wazig/pr-journeys.json').read_text())
    journeys = json.loads((ROOT / 'tools/verify-wazig/journeys.json').read_text())['journeys']
    commits = runner(['git', 'log', '--first-parent', '--format=%H',
                      f'refs/tags/{previous}..refs/tags/{tag}']).splitlines()
    failed = False
    changed = False
    checked = set()
    for sha in commits:
        context = f'commit {sha}'
        try:
            files = runner(['git', 'diff-tree', '--root', '--first-parent', '-m', '-r',
                            '--no-commit-id', '--name-only', '--no-renames', '-z', sha]).split('\0')
            if not any(path.startswith('src/') or path == 'build.zig'
                       or any(path.startswith(prefix) for prefix in mapping['paths']) for path in files):
                continue
            changed = True
            pulls = api_pages(f'repos/{repo}/commits/{sha}/pulls', runner)
            pulls = [pull for pull in pulls if pull.get('merged_at')]
            if not pulls:
                print(f'MISSING: {context}: no PR, no recorded proof')
                failed = True
                continue
            for pull in pulls:
                number = pull['number']
                context = f'commit {sha}, PR #{number}'
                if number in checked:
                    continue
                checked.add(number)
                rows = api_pages(f'repos/{repo}/pulls/{number}/files', runner)
                if len(rows) >= 3000:
                    raise ValueError('PR file list reached the GitHub limit; cannot prove every changed feature')
                files = []
                for row in rows:
                    files.append(row['filename'])
                    if 'previous_filename' in row:
                        files.append(row['previous_filename'])
                names = plan_journeys(files, mapping, journeys)
                if not names:
                    raise ValueError('changed app features have no selected journeys')
                head = pull['head']['sha']
                runs = api_pages(f'repos/{repo}/actions/workflows/verify.yml/runs?head_sha={head}&event=pull_request',
                                 runner, 'workflow_runs')
                successful = [row for row in runs if row['head_sha'] == head and row['event'] == 'pull_request'
                              and row['status'] == 'completed' and row['conclusion'] == 'success']
                if not successful:
                    for name in sorted(names):
                        print(f'MISSING: {context}, journey {name}: no successful verify-wazig PR run on head {head}')
                    failed = True
                    continue
                run_id = max(successful, key=lambda row: row['id'])['id']
                artifacts = api_pages(f'repos/{repo}/actions/runs/{run_id}/artifacts', runner, 'artifacts')
                for name in sorted(names):
                    label = f'{context}, journey {name}'
                    artifact_name = f'verify-wazig-{name}'
                    artifact = next((row for row in artifacts if row['name'] == artifact_name), None)
                    problem = None
                    if artifact is None:
                        problem = f'missing artifact {artifact_name}'
                    elif artifact['expired']:
                        problem = f'expired artifact {artifact_name}'
                    elif artifact['size_in_bytes'] <= 0:
                        problem = f'empty artifact {artifact_name}'
                    else:
                        try:
                            with tempfile.TemporaryDirectory() as directory:
                                runner(['gh', 'run', 'download', str(run_id), '--repo', repo,
                                        '-n', artifact_name, '-D', directory])
                                root = Path(directory)
                                log = root / 'run.log'
                                if not log.is_file() or log.stat().st_size == 0:
                                    problem = 'missing non-empty run.log'
                                elif not any(path.is_file() and path.suffix.lower() in ('.png', '.mp4')
                                             and path.stat().st_size > 0 for path in root.rglob('*')):
                                    problem = 'missing non-empty .png screenshot or .mp4 recording'
                        except (OSError, subprocess.CalledProcessError):
                            problem = f'could not download or read artifact {artifact_name}'
                    print(f'MISSING: {label}: {problem}' if problem else f'{label}: ok')
                    failed |= problem is not None
        except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
            problem = 'could not read release history or PR proof' if isinstance(error, subprocess.CalledProcessError) else str(error)
            print(f'MISSING: {context}: {problem}')
            failed = True
    if not changed and not failed:
        print(f'{previous}..{tag}: no changed app features')
    return int(failed)


def main():
    parser = argparse.ArgumentParser(description='Require recorded PR journey proof before publishing a release')
    parser.add_argument('--repo', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--previous')
    args = parser.parse_args()
    try:
        return check_release_proof(args.repo, args.tag, args.previous)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        problem = 'could not read release tags or commits' if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f'MISSING: {problem}')
        return 1


if __name__ == '__main__':
    sys.exit(main())
