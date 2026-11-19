import json
import tempfile
import unittest
from pathlib import Path

import check_job_budget as budget

ROOT = Path(__file__).resolve().parent.parent


def fixture(files, default=('search', 'voice', 'reply')):
    folder = Path(tempfile.mkdtemp())
    (folder / '.github/workflows').mkdir(parents=True)
    (folder / 'tools/verify-wazig').mkdir(parents=True)
    (folder / 'tools/verify-wazig/pr-journeys.json').write_text(json.dumps({'default': list(default)}))
    for name, text in files.items():
        (folder / '.github/workflows' / name).write_text(text)
    return folder


def workflow(trigger, job_names, extra=''):
    jobs = ''.join(f'  {name}:\n    runs-on: ubuntu-latest\n{extra}' for name in job_names)
    return f'name: x\non:\n  {trigger}\njobs:\n{jobs}'


class JobBudgetTests(unittest.TestCase):
    def test_repo_is_within_budget(self):
        total, _ = budget.count_pr_jobs(ROOT)
        self.assertLessEqual(total, budget.BUDGET)

    def test_counts_pull_request_jobs(self):
        folder = fixture({'a.yml': workflow('pull_request:\n', ['one', 'two'])})
        self.assertEqual(budget.count_pr_jobs(folder)[0], 2)

    def test_ignores_workflows_without_pull_request(self):
        folder = fixture({'a.yml': workflow('push:\n', ['one', 'two'])})
        self.assertEqual(budget.count_pr_jobs(folder)[0], 0)

    def test_ignores_pull_request_target(self):
        folder = fixture({'a.yml': workflow('pull_request_target:\n', ['one'])})
        self.assertEqual(budget.count_pr_jobs(folder)[0], 0)

    def test_ignores_path_filtered_workflows(self):
        text = 'name: x\non:\n  pull_request:\n    paths:\n      - src/a.zig\njobs:\n  one:\n    runs-on: ubuntu-latest\n'
        self.assertEqual(budget.count_pr_jobs(fixture({'a.yml': text}))[0], 0)

    def test_ignores_nightly_only_jobs(self):
        extra = "    if: ${{ github.event_name == 'schedule' }}\n"
        folder = fixture({'a.yml': workflow('pull_request:\n', ['nightly'], extra)})
        self.assertEqual(budget.count_pr_jobs(folder)[0], 0)

    def test_matrix_counts_each_default_journey(self):
        extra = '    strategy:\n      matrix: ${{ fromJSON(needs.plan.outputs.matrix) }}\n'
        folder = fixture({'a.yml': workflow('pull_request:\n', ['verify'], extra)})
        self.assertEqual(budget.count_pr_jobs(folder)[0], 3)

    def test_many_jobs_exceed_the_budget(self):
        names = [f'job-{n}' for n in range(budget.BUDGET + 1)]
        folder = fixture({'a.yml': workflow('pull_request:\n', names)})
        self.assertGreater(budget.count_pr_jobs(folder)[0], budget.BUDGET)


if __name__ == '__main__':
    unittest.main()
