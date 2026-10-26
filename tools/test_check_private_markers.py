import io
import os
import subprocess
import tempfile
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from unittest import mock

import check_private_markers
from check_private_markers import load_markers, private_paths, scan_text

PLANTED = "Install every new release on his PC (ZZDEVICE) right away."


class PrivateMarkers(unittest.TestCase):
    def test_planted_marker_is_found(self):
        markers = load_markers("\\bZZDEVICE\\b\n")
        self.assertEqual(scan_text("CLAUDE.md", "ok\n" + PLANTED, markers), [("CLAUDE.md", 2, 1)])

    def test_word_boundary_and_case(self):
        markers = load_markers("\\bZZDEVICE\\b")
        self.assertEqual(scan_text("a", "zzdevice ZZDEVICES xZZDEVICE", markers), [])

    def test_blank_lines_are_not_markers(self):
        self.assertEqual(len(load_markers("\n  \nA\n\n")), 1)

    def test_empty_secret_fails_closed(self):
        with mock.patch.dict(os.environ, {"PRIVATE_MARKERS": ""}):
            self.assertEqual(check_private_markers.main([]), 2)

    def test_pr_body_is_scanned(self):
        env = {"PRIVATE_MARKERS": "ZZDEVICE", "PR_TITLE": "fine", "PR_BODY": "tested on ZZDEVICE"}
        with mock.patch.dict(os.environ, env), mock.patch.object(check_private_markers, "git", return_value=b""):
            self.assertEqual(check_private_markers.scan_pr(load_markers("ZZDEVICE"), "a", "b"), [("PR body", 1, 1)])

    def test_nested_log_marker_uses_relative_label(self):
        with tempfile.TemporaryDirectory() as directory:
            nested = Path(directory, "run", "job.log")
            nested.parent.mkdir()
            nested.write_text("clean\nprivate-pattern\n", encoding="utf-8")
            output = io.StringIO()
            with mock.patch.dict(os.environ, {"PRIVATE_MARKERS": "private-pattern"}), redirect_stdout(output):
                self.assertEqual(check_private_markers.main(["--logs", directory]), 1)
            self.assertEqual(output.getvalue(), "run/job.log:2: private marker #1. Move this to the private companion repo or reword it.\n")

    def test_clean_log_directory_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "job.log").write_text("ordinary output\n", encoding="utf-8")
            output = io.StringIO()
            with mock.patch.dict(os.environ, {"PRIVATE_MARKERS": "private-pattern"}), redirect_stdout(output):
                self.assertEqual(check_private_markers.main(["--logs", directory]), 0)
            self.assertEqual(output.getvalue(), "No private markers (1 checked).\n")

    def test_binary_logs_are_skipped(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "binary.log").write_bytes(b"\0private-pattern")
            self.assertEqual(check_private_markers.scan_logs(load_markers("private-pattern"), directory), [])

    def test_missing_log_directory_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(os.environ, {"PRIVATE_MARKERS": "private-pattern"}), redirect_stdout(io.StringIO()):
                self.assertEqual(check_private_markers.main(["--logs", str(Path(directory, "missing"))]), 2)

    def test_private_agent_files_are_refused(self):
        paths = ["HANDOFF.md", ".claude/skills/INDEX.md", ".claude/skills", "board.yml", "src/main.zig", ".claude/hooks/preflight-guard.sh"]
        self.assertEqual(private_paths(paths), ["HANDOFF.md", ".claude/skills/INDEX.md", ".claude/skills", "board.yml"])

    def test_only_named_public_skill_files_are_allowed(self):
        private = [".claude/skills/verify-wazig/private.md", ".claude/skills/verify-wazig/features/private.md", ".claude/skills/verify-wazig-other/SKILL.md"]
        self.assertEqual(private_paths(list(check_private_markers.PUBLIC_SKILL_PATHS) + [".claude/skills/verify-wazig/features/menus.md"] + private), private)

    def test_public_skill_content_still_rejects_private_markers(self):
        for path in [".claude/skills/verify-wazig/SKILL.md", ".claude/skills/verify-wazig/features/menus.md"]:
            with self.subTest(path=path), mock.patch.object(check_private_markers, "git", return_value=path.encode()), mock.patch.object(os.path, "isfile", return_value=True), mock.patch("builtins.open", mock.mock_open(read_data=b"ZZDEVICE")):
                self.assertEqual(check_private_markers.scan_tree(load_markers("ZZDEVICE")), [(path, 1, 1)])

    def test_untracked_files_are_scanned_and_ignored_ones_skipped(self):
        with tempfile.TemporaryDirectory() as directory:
            run = lambda *args: subprocess.run(["git", "-C", directory, *args], check=True, capture_output=True)
            run("init", "-q")
            Path(directory, ".gitignore").write_text("hidden.txt\n")
            Path(directory, "tracked.txt").write_text("clean\n")
            run("add", ".")
            Path(directory, "fresh.txt").write_text("ZZDEVICE\n")
            Path(directory, "hidden.txt").write_text("ZZDEVICE\n")
            previous = os.getcwd()
            os.chdir(directory)
            try:
                hits = check_private_markers.scan_tree(load_markers("ZZDEVICE"))
            finally:
                os.chdir(previous)
        self.assertEqual(hits, [("fresh.txt", 1, 1)])


if __name__ == "__main__":
    unittest.main()
