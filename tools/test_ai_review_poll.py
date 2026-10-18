import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SHA = "a" * 40
MARKER = "<!-- wazig-ai-review -->"
FAKE_CLI = '''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["FIXTURE_ROOT"])
config = json.loads((root / "config.json").read_text())
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as handle:
    handle.write(json.dumps([Path(sys.argv[0]).name, *args]) + "\\n")
if Path(sys.argv[0]).name == "git":
    if args == ["rev-parse", "--show-toplevel"]:
        print(root)
    elif args == ["status", "--porcelain"] and config.get("dirty", True):
        print(" M tracked")
    elif args[:1] == ["fetch"] and config.get("fail_fetch"):
        sys.exit(1)
elif args[:2] == ["pr", "list"]:
    if config.get("fail_listing"):
        sys.exit(1)
    print(json.dumps(config["prs"]))
elif args[:1] == ["api"]:
    pr = args[1].split("/")[-2]
    if pr in config.get("fail_comments", []):
        sys.exit(1)
    for comment in config.get("comments", {}).get(pr, []):
        print(json.dumps(comment))
else:
    sys.exit(2)
'''
REVIEW = '''#!/usr/bin/env bash
printf '%s\\n' "$1" >> "$FIXTURE_ROOT/reviews"
[[ ! -f "$FIXTURE_ROOT/fail-review-$1" ]]
'''


class ReviewPoll(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "bin").mkdir()
        (self.root / "runtime").mkdir()
        (self.root / "tools").mkdir()
        for name in ("gh", "git"):
            path = self.root / "bin" / name
            path.write_text(FAKE_CLI)
            path.chmod(0o755)
        shutil.copyfile(Path(__file__).with_name("ai-review-poll.sh"), self.root / "tools/ai-review-poll.sh")
        (self.root / "tools/ai-review.sh").write_text(REVIEW)
        self.env = dict(os.environ, FIXTURE_ROOT=str(self.root), XDG_STATE_HOME=str(self.root / "state"),
                        XDG_RUNTIME_DIR=str(self.root / "runtime"), PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                        GITHUB_REPOSITORY="example/project", AI_REVIEW_DRY_RUN="0")
        self.config = {"prs": [self.pr(1)], "comments": {}}

    def pr(self, number, fork=False, sha=SHA):
        return {"number": number, "headRefOid": sha, "isCrossRepository": fork}

    def bot(self, sha=SHA, number=1, created="2026-01-01T00:00:00Z", updated="2026-01-01T00:00:00Z"):
        return {"id": number, "body": f"{MARKER}\nCommit {sha}\n", "user": {"login": "github-actions[bot]", "type": "Bot"},
                "created_at": created, "updated_at": updated}

    def request(self, number=2, association="OWNER", kind="User", created="2026-01-02T00:00:00Z"):
        return {"id": number, "body": "/ai-review please", "user": {"login": "review-request", "type": kind},
                "author_association": association, "created_at": created, "updated_at": created}

    def run_poll(self, dry=False):
        (self.root / "config.json").write_text(json.dumps(self.config))
        return subprocess.run(["bash", "tools/ai-review-poll.sh"], cwd=self.root,
                              env=dict(self.env, AI_REVIEW_DRY_RUN="1" if dry else "0"),
                              capture_output=True, text=True, timeout=10)

    def reviews(self):
        path = self.root / "reviews"
        return path.read_text().splitlines() if path.exists() else []

    def test_dry_run_skips_forks_and_writes_no_state_or_git_refresh(self):
        self.config["prs"].append(self.pr(2, fork=True))
        result = self.run_poll(dry=True)
        self.assertEqual((result.returncode, result.stdout), (0, "due 1 head\n"))
        self.assertFalse((self.root / "state").exists())
        self.assertEqual(list((self.root / "runtime").iterdir()), [])
        calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertEqual([call for call in calls if call[0] == "git"], [["git", "rev-parse", "--show-toplevel"]])
        self.assertEqual(self.reviews(), [])

    def test_success_suppresses_dispatch_before_bot_post(self):
        self.assertIn("PR 1 dispatched (head)", self.run_poll().stdout)
        self.assertNotIn("PR 1", self.run_poll().stdout)
        self.assertEqual(self.reviews(), ["1"])

    def test_failure_retries_at_most_twice_and_continues(self):
        (self.root / "fail-review-1").touch()
        self.config["prs"].append(self.pr(2))
        for _ in range(3):
            self.assertEqual(self.run_poll().returncode, 0)
        self.assertEqual(self.reviews(), ["1", "2", "1"])

    def test_new_authorized_request_runs_once_after_done(self):
        self.run_poll()
        self.config["comments"]["1"] = [self.bot(), self.request()]
        self.assertIn("PR 1 dispatched (request)", self.run_poll().stdout)
        self.assertNotIn("PR 1", self.run_poll().stdout)
        self.assertEqual(self.reviews(), ["1", "1"])
        self.assertTrue((self.root / "state/wazig-ai-review/handled/2").exists())

    def test_failed_request_is_not_handled_twice(self):
        self.config["comments"]["1"] = [self.bot(), self.request()]
        (self.root / "fail-review-1").touch()
        self.assertIn("PR 1 failed (request)", self.run_poll().stdout)
        self.assertNotIn("PR 1", self.run_poll().stdout)
        self.assertEqual(self.reviews(), ["1"])

    def test_requests_require_trusted_human_and_newer_creation(self):
        for request in (self.request(association="CONTRIBUTOR"), self.request(kind="Bot"),
                        self.request(created="2026-01-01T00:00:00Z")):
            self.config["comments"]["1"] = [self.bot(), request]
            self.assertEqual(self.run_poll(dry=True).stdout, "")
        for association in ("OWNER", "MEMBER", "COLLABORATOR"):
            self.config["comments"]["1"] = [self.bot(), self.request(association=association)]
            self.assertEqual(self.run_poll(dry=True).stdout, "due 1 request\n")

    def test_newest_bot_comment_wins_and_old_request_is_not_due(self):
        self.config["comments"]["1"] = [self.bot(sha="b" * 40), self.request(),
                                         self.bot(number=3, created="2026-01-03T00:00:00Z", updated="2026-01-04T00:00:00Z")]
        self.assertEqual(self.run_poll(dry=True).stdout, "")

    def test_changed_head_is_due(self):
        self.config["comments"]["1"] = [self.bot(sha="b" * 40)]
        self.assertEqual(self.run_poll(dry=True).stdout, "due 1 head\n")

    def test_comment_failure_continues_but_listing_failure_exits_one(self):
        self.config.update(fail_comments=["1"], prs=[self.pr(1), self.pr(2)])
        result = self.run_poll()
        self.assertEqual(result.returncode, 0)
        self.assertIn("PR 1 comments failed", result.stdout)
        self.assertEqual(self.reviews(), ["2"])
        self.config["fail_listing"] = True
        self.assertEqual(self.run_poll().returncode, 1)

    def test_clean_tree_refreshes_only_main_and_dirty_tree_does_not(self):
        self.config["dirty"] = False
        self.run_poll()
        calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertIn(["git", "fetch", "-q", "origin", "main"], calls)
        self.assertIn(["git", "checkout", "-q", "--detach", "origin/main"], calls)
        (self.root / "calls.jsonl").unlink()
        self.config["dirty"] = True
        self.assertIn("tree is dirty; refresh skipped", self.run_poll().stdout)
        calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertFalse(any(call[1] in ("fetch", "checkout") for call in calls if call[0] == "git"))

    def test_overlapping_run_exits_zero_without_listing(self):
        import fcntl

        with (self.root / "runtime/wazig-ai-review.lock").open("w") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_poll()
        self.assertEqual((result.returncode, result.stdout), (0, ""))
        calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertFalse(any(call[0] == "gh" for call in calls))


if __name__ == "__main__":
    unittest.main()
