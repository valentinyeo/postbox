import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VW = ROOT / "tools" / "verify-wazig" / "vw.py"


def vw(*args, env=None):
    merged = dict(os.environ)
    merged.update(env or {})
    return subprocess.run([sys.executable, str(VW), *args], capture_output=True, text=True, env=merged)


class VwTests(unittest.TestCase):
    def test_journeys_lists_the_registry(self):
        result = vw("journeys")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        registry = json.loads((ROOT / "tools/verify-wazig/journeys.json").read_text())["journeys"]
        self.assertEqual(data["count"], len(registry))
        self.assertTrue(all(row["has_planted_bug"] for row in data["journeys"]))

    def test_unknown_journey_names_the_next_step(self):
        result = vw("describe", "no-such-journey")
        self.assertEqual(result.returncode, 2)
        error = json.loads(result.stderr)
        self.assertIn("no-such-journey", error["error"])
        self.assertIn("journeys", error["next"])

    def test_run_dry_run_prints_the_dispatch_and_runs_nothing(self):
        result = vw("run", "search", "--ref", "main", "--repeat", "2", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        command = json.loads(result.stdout)["command"]
        self.assertEqual(command[:4], ["gh", "workflow", "run", "verify.yml"])
        self.assertIn("feature=search", command)
        self.assertIn("repeat=2", command)

    def test_run_rejects_bad_repeat(self):
        result = vw("run", "search", "--repeat", "9", "--dry-run")
        self.assertEqual(result.returncode, 2)
        self.assertIn("repeat", json.loads(result.stderr)["error"])

    def test_drive_dry_run_builds_the_runner_command(self):
        result = vw("drive", "search", "--evidence", "e1", "--expected-version", "1.2.3", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        command = json.loads(result.stdout)["command"]
        self.assertIn("-Feature", command)
        self.assertIn("search", command)
        self.assertEqual(command[command.index("-ExpectedVersion") + 1], "1.2.3")

    def test_drive_passes_the_exit_code_through(self):
        with tempfile.TemporaryDirectory() as folder:
            fake = Path(folder) / "pwsh"
            fake.write_text("#!/bin/sh\nexit 7\n")
            fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
            result = vw("drive", "search", env={"VW_PWSH": str(fake)})
        self.assertEqual(result.returncode, 7)

    def test_ctl_write_needs_allow_write(self):
        result = vw("ctl", "--", "archive", "x")
        self.assertEqual(result.returncode, 2)
        self.assertIn("--dry-run", json.loads(result.stderr)["next"])

    def test_ctl_read_dry_run_is_not_mutating(self):
        result = vw("ctl", "--dry-run", "--", "status")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertFalse(data["mutating"])
        self.assertTrue(data["command"][0].endswith("wazigctl.exe"))
        self.assertEqual(data["command"][1], "status")

    def test_ctl_missing_binary_says_how_to_build(self):
        result = vw("ctl", "--bin", "/nonexistent", "--", "status")
        self.assertEqual(result.returncode, 3)
        self.assertIn("zig build wazigctl", json.loads(result.stderr)["next"])

    def test_help_lists_every_subcommand(self):
        result = vw("--help")
        self.assertEqual(result.returncode, 0)
        for name in ("journeys", "describe", "run", "runs", "status", "evidence", "drive", "ctl"):
            self.assertIn(name, result.stdout)


if __name__ == "__main__":
    unittest.main()
